#!/usr/bin/env bash
# usms-scaling-report.sh - decision table and verdict for every usms- scalable target.
#
# set -e is deliberately NOT used: a describe call that Floci does not implement
# (scheduled actions, scaling activities) is expected data, not a fatal error, and
# -e would abort the whole report on the first one. -u and pipefail still catch typos.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ROOT
if [ -f "$ROOT/configs/course.env" ]; then set +u; . "$ROOT/configs/course.env"; set -u; fi
mkdir -p "$ROOT/outputs"

python3 - << 'PY'
import json, os, re, subprocess, sys

ROOT = os.environ["ROOT"]

def aws(*args):
    """Run an aws call. Returns parsed JSON, or None if the call failed."""
    try:
        p = subprocess.run(["aws", *args, "--output", "json"], capture_output=True, text=True)
    except OSError:
        return None
    if p.returncode != 0:
        return None
    try:
        return json.loads(p.stdout) if p.stdout.strip() else {}
    except ValueError:
        return None

OPS = {"GreaterThanThreshold": ">", "GreaterThanOrEqualToThreshold": ">=",
       "LessThanThreshold": "<", "LessThanOrEqualToThreshold": "<="}
METRICS = {"ECSServiceAverageCPUUtilization": "CPU",
           "ECSServiceAverageMemoryUtilization": "MEM",
           "ALBRequestCountPerTarget": "ALBReq"}

def row(kind, text):
    print(f"  {kind:<12} {text}")

def sub(text):
    print(f"  {'':<12}   {text}")

resp = aws("application-autoscaling", "describe-scalable-targets", "--service-namespace", "ecs")
if resp is None:
    print("cannot reach Application Auto Scaling - is Floci up?")
    sys.exit(1)
targets = [t for t in resp.get("ScalableTargets", [])
           if re.match(r"^service/usms-[^/]+/[^/]+$", t["ResourceId"])]
if not targets:
    print("no scalable targets for a usms- cluster in the ecs namespace")
    sys.exit(0)

al = aws("cloudwatch", "describe-alarms") or {}
alarms = al.get("MetricAlarms", [])
by_name = {a["AlarmName"]: a for a in alarms}
by_action = {}
for a in alarms:
    for arn in a.get("AlarmActions", []):
        by_action.setdefault(arn, []).append(a)

def alarms_for(p):
    seen = {}
    for x in p.get("Alarms") or []:
        a = by_name.get(x.get("AlarmName"))
        if a:
            seen[a["AlarmName"]] = a
    for a in by_action.get(p["PolicyARN"], []):
        seen[a["AlarmName"]] = a
    return sorted(seen.values(), key=lambda a: (0 if "AlarmHigh" in a["AlarmName"] else 1, a["AlarmName"]))

def signed(adj_type, v):
    v = int(v)
    if adj_type == "PercentChangeInCapacity":
        return f"{v:+d}%"
    if adj_type == "ExactCapacity":
        return f"={v}"
    return f"{v:+d}"

report = []
for t in targets:
    rid, dim = t["ResourceId"], t["ScalableDimension"]
    _, cluster, service = rid.split("/")
    mn, mx = t["MinCapacity"], t["MaxCapacity"]

    ecs = aws("ecs", "describe-services", "--cluster", cluster, "--services", service)
    svc = (ecs or {}).get("services") or []
    desired = svc[0].get("desiredCount") if svc else None
    running = svc[0].get("runningCount") if svc else None

    pol = aws("application-autoscaling", "describe-scaling-policies", "--service-namespace", "ecs",
              "--resource-id", rid, "--scalable-dimension", dim)
    policies = sorted((pol or {}).get("ScalingPolicies", []), key=lambda p: p["PolicyName"])

    susp = [k.replace("Suspended", "") for k, v in (t.get("SuspendedState") or {}).items() if v]

    # Verdict, evaluated top to bottom. PINNED first: if min == max nothing else matters,
    # the service cannot scale whatever the switches say. FROZEN before AT-CEILING and
    # AT-FLOOR: a suspended target is not scaling at all, and "at ceiling" or "at floor"
    # would make a silent, dangerous state look like a healthy, merely maxed-out one.
    if mn == mx:
        verdict = "PINNED"
    elif susp:
        verdict = "FROZEN"
    elif desired is not None and desired == mx:
        verdict = "AT-CEILING"
    elif desired is not None and desired == mn and len(policies) > 1:
        verdict = "AT-FLOOR"
    else:
        verdict = "ELASTIC"

    print(f"{rid} {dim}")
    row("bounds", f"min={mn} max={mx} desired={desired if desired is not None else '?'} "
                  f"running={running if running is not None else '?'} {verdict}")
    row("suspended", ", ".join(susp) if susp else "none")

    rec_pol = []
    if not policies:
        row("policies", "none")
    for p in policies:
        name, typ = p["PolicyName"], p["PolicyType"]
        linked = alarms_for(p)
        if typ == "TargetTrackingScaling":
            c = p["TargetTrackingScalingPolicyConfiguration"]
            spec = c.get("PredefinedMetricSpecification") or {}
            metric = METRICS.get(spec.get("PredefinedMetricType"), spec.get("PredefinedMetricType", "custom"))
            row("target-track", f"{name:<44} {metric}/{c['TargetValue']}  "
                                f"out={c.get('ScaleOutCooldown', 0)} in={c.get('ScaleInCooldown', 0)}"
                                f"{'  scale-in OFF' if c.get('DisableScaleIn') else ''}")
            if linked:
                sub("alarms " + " ".join(f"{a['AlarmName'].split('-')[-5] if False else ('AlarmHigh' if 'AlarmHigh' in a['AlarmName'] else 'AlarmLow' if 'AlarmLow' in a['AlarmName'] else a['AlarmName'])}={a['StateValue']}" for a in linked))
            else:
                sub("alarms none found")
        elif typ == "StepScaling":
            c = p["StepScalingPolicyConfiguration"]
            steps = sorted(c.get("StepAdjustments", []),
                           key=lambda s: s.get("MetricIntervalLowerBound", float("-inf")))
            summary = " / ".join(signed(c.get("AdjustmentType"), s["ScalingAdjustment"]) for s in steps)
            row("step", f"{name:<44} {summary}  cooldown={c.get('Cooldown', 0)}")
            if linked:
                for a in linked:
                    sub(f"alarm {a['AlarmName']} = {a['StateValue']} "
                        f"({a.get('Namespace', '?')} {a.get('MetricName', '?')} "
                        f"{OPS.get(a.get('ComparisonOperator'), '?')} {a.get('Threshold')})")
            else:
                sub("alarm none invokes this policy")
        else:
            row("policy", f"{name} ({typ})")
        rec_pol.append({"name": name, "type": typ, "alarms": [a["AlarmName"] for a in linked]})

    sched = aws("application-autoscaling", "describe-scheduled-actions", "--service-namespace", "ecs",
                "--resource-id", rid)
    rec_sched = None
    if sched is None:
        row("scheduled", "unavailable (describe-scheduled-actions failed on this build)")
    elif not sched.get("ScheduledActions"):
        row("scheduled", "none")
        rec_sched = []
    else:
        rec_sched = []
        for s in sorted(sched["ScheduledActions"], key=lambda s: s["ScheduledActionName"]):
            act = s.get("ScalableTargetAction") or {}
            bits = [f"{k[:3].lower()}={v}" for k, v in act.items() if k in ("MinCapacity", "MaxCapacity")]
            row("scheduled", f"{s['ScheduledActionName']} {s.get('Schedule', '?')} "
                             f"{s.get('Timezone', 'UTC')} {' '.join(bits)}")
            rec_sched.append(s["ScheduledActionName"])

    acts = aws("application-autoscaling", "describe-scaling-activities", "--service-namespace", "ecs",
               "--resource-id", rid, "--scalable-dimension", dim, "--max-items", "1")
    last = None
    if acts is None:
        row("last activity", "unavailable (describe-scaling-activities failed on this build)")
    elif not acts.get("ScalingActivities"):
        row("last activity", "none recorded")
    else:
        a = acts["ScalingActivities"][0]
        last = a.get("Description")
        row("last activity", f"{str(a.get('StartTime', '?'))[:19]} {a.get('StatusCode', '?')} "
                             f"{str(a.get('Description', ''))[:70]}")
    print()

    report.append({"resourceId": rid, "dimension": dim, "min": mn, "max": mx,
                   "desired": desired, "running": running, "suspended": susp,
                   "verdict": verdict, "policies": rec_pol,
                   "scheduledActions": rec_sched, "lastActivity": last})

with open(os.path.join(ROOT, "outputs", "lab-06-scaling-report.json"), "w") as f:
    json.dump(report, f, indent=2)
PY
