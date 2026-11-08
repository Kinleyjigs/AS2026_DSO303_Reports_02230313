#!/usr/bin/env bash
# usms-scaling-history.sh - export the scaling configuration and history of the usms- service
# as one JSON document: outputs/lab-06-scaling-history.json.
# No set -e: an unimplemented describe call is recorded as null, not a reason to stop.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ROOT
if [ -f "$ROOT/configs/course.env" ]; then set +u; . "$ROOT/configs/course.env"; set -u; fi
mkdir -p "$ROOT/outputs"

python3 - << 'PY'
import datetime, json, os, re, subprocess, sys

ROOT = os.environ["ROOT"]

def aws(*args):
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

resp = aws("application-autoscaling", "describe-scalable-targets", "--service-namespace", "ecs")
if resp is None:
    print("cannot reach Application Auto Scaling - is Floci up?", file=sys.stderr)
    sys.exit(1)
targets = sorted((t for t in resp.get("ScalableTargets", [])
                  if re.match(r"^service/usms-[^/]+/[^/]+$", t["ResourceId"])),
                 key=lambda t: t["ResourceId"])
if not targets:
    print("no usms- scalable target found", file=sys.stderr)
    sys.exit(1)
if len(targets) > 1:
    print(f"warning: {len(targets)} usms- targets found, exporting the first", file=sys.stderr)

target = targets[0]
rid, dim = target["ResourceId"], target["ScalableDimension"]
_, cluster, service = rid.split("/")

svc = ((aws("ecs", "describe-services", "--cluster", cluster, "--services", service) or {})
       .get("services") or [{}])[0]
service_arn = svc.get("serviceArn", "")
resource_id = service_arn.split(":")[-1] if service_arn else rid

policies = (aws("application-autoscaling", "describe-scaling-policies", "--service-namespace", "ecs",
                "--resource-id", rid, "--scalable-dimension", dim) or {}).get("ScalingPolicies", [])
sched = aws("application-autoscaling", "describe-scheduled-actions", "--service-namespace", "ecs",
            "--resource-id", rid)
scheduled = None if sched is None else sched.get("ScheduledActions", [])

policy_arns = {p["PolicyARN"] for p in policies}
alarm_names = {a["AlarmName"] for p in policies for a in (p.get("Alarms") or [])}
all_alarms = (aws("cloudwatch", "describe-alarms") or {}).get("MetricAlarms", [])
alarms = [a for a in all_alarms
          if a["AlarmName"] in alarm_names or policy_arns & set(a.get("AlarmActions", []))]

acts = aws("application-autoscaling", "describe-scaling-activities", "--service-namespace", "ecs",
           "--resource-id", rid, "--scalable-dimension", dim, "--include-not-scaled")
if acts is None:
    acts = aws("application-autoscaling", "describe-scaling-activities", "--service-namespace", "ecs",
               "--resource-id", rid, "--scalable-dimension", dim)
activities = None if acts is None else acts.get("ScalingActivities", [])

doc = {
    "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "resourceId": resource_id,
    "service": {"cluster": cluster, "name": service, "arn": service_arn,
                "desiredCount": svc.get("desiredCount"), "runningCount": svc.get("runningCount")},
    "scalableTarget": target,
    "scalingPolicies": policies,
    "scheduledActions": scheduled,
    "alarms": alarms,
    "scalingActivities": activities,
}
path = os.path.join(ROOT, "outputs", "lab-06-scaling-history.json")
with open(path, "w") as f:
    json.dump(doc, f, indent=2, default=str)
print(path)
PY
