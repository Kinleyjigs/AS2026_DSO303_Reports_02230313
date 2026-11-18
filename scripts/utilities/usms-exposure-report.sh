#!/usr/bin/env bash
# USMS exposure report (Lab 09 Exercise 3).
#
# One line per network interface in usms-vpc, with a verdict computed from BOTH axes:
#   routing   - the interface's subnet route table (explicit association, else the VPC main table)
#   address   - whether the interface has a public IPv4 address
#   groups    - whether any of its security groups admits 0.0.0.0/0 (or ::/0), and on what
# Never from names, tags or descriptions.
#
# Verdicts:
#   INTERNET-EXPOSED    public address + IGW default route + a group admitting the internet
#   PUBLIC-BUT-CLOSED   public address + IGW route, but no group admits the internet
#                       (includes a group with NO ingress rule at all - see the note below)
#   PRIVATE-EGRESS      no public address; default route via NAT (can call out, cannot be called)
#   ISOLATED            no public address and no default route at all
#   NOT-ADDRESSABLE     IGW route but no public address: unreachable, held up by one control
#   + ORPHAN tag        interface not attached, or attached to a terminated instance
#
# Decision for a public interface with no ingress rule at all: PUBLIC-BUT-CLOSED, not "safe".
# Today nothing can reach it, but it is ONE rule change away from exposure, because the other two
# controls (address, route) are already open. It is reported so a human decides whether the
# public address should exist at all.
#
# set -u and pipefail, but NOT -e: this is a report. One failing describe call (a group we cannot
# read, a subnet that vanished) must produce an "unknown" line, not kill the whole report.
# Read-only. Writes outputs/lab-09-exposure.json. Always exits 0.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1090
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true
# shellcheck disable=SC1090
source "$REPO_ROOT/configs/lab-02.env" 2>/dev/null || true

VPC="${USMS_VPC_ID:-}"
if [ -z "$VPC" ] || [ "$VPC" = "none" ]; then
  VPC=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=usms-vpc" \
          --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
fi
[ -n "$VPC" ] && [ "$VPC" != "None" ] || { echo "cannot find usms-vpc" >&2; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC" --output json > "$TMP/eni.json" 2>/dev/null || echo '{"NetworkInterfaces":[]}' > "$TMP/eni.json"
aws ec2 describe-security-groups   --filters "Name=vpc-id,Values=$VPC" --output json > "$TMP/sg.json"  2>/dev/null || echo '{"SecurityGroups":[]}'   > "$TMP/sg.json"
aws ec2 describe-route-tables      --filters "Name=vpc-id,Values=$VPC" --output json > "$TMP/rt.json"  2>/dev/null || echo '{"RouteTables":[]}'      > "$TMP/rt.json"
aws ec2 describe-instances         --filters "Name=vpc-id,Values=$VPC" --output json > "$TMP/ec2.json" 2>/dev/null || echo '{"Reservations":[]}'     > "$TMP/ec2.json"

python3 - "$TMP" "$REPO_ROOT/outputs/lab-09-exposure.json" << 'PY'
import json, subprocess, sys

tmp, out_path = sys.argv[1], sys.argv[2]
enis   = json.load(open(f"{tmp}/eni.json")).get("NetworkInterfaces", [])
groups = {g["GroupId"]: g for g in json.load(open(f"{tmp}/sg.json")).get("SecurityGroups", [])}
rts    = json.load(open(f"{tmp}/rt.json")).get("RouteTables", [])
state  = {i["InstanceId"]: i.get("State", {}).get("Name")
          for r in json.load(open(f"{tmp}/ec2.json")).get("Reservations", [])
          for i in r.get("Instances", [])}

def group(gid):
    """A group not in the VPC cache (shared, or created since) is fetched on its own."""
    if gid not in groups:
        p = subprocess.run(["aws", "ec2", "describe-security-groups", "--group-ids", gid, "--output", "json"],
                           capture_output=True, text=True)
        try:
            groups[gid] = json.loads(p.stdout)["SecurityGroups"][0]
        except Exception:
            groups[gid] = None
    return groups[gid]

main_rt = next((t for t in rts if any(a.get("Main") for a in t.get("Associations", []))), None)
def route_table(subnet):
    for t in rts:
        if any(a.get("SubnetId") == subnet for a in t.get("Associations", [])):
            return t
    return main_rt            # no explicit association -> the VPC's main table

def default_route(t):
    if not t:
        return "none"
    for r in t.get("Routes", []):
        if r.get("DestinationCidrBlock") == "0.0.0.0/0":
            if (r.get("GatewayId") or "").startswith("igw-"):
                return "igw"
            if r.get("NatGatewayId"):
                return "nat"
            return "other"
    return "none"

def internet_ingress(gids):
    """Ports a group admits from 0.0.0.0/0 or ::/0; None if a group could not be read."""
    ports, unknown, any_rule = [], False, False
    for gid in gids:
        g = group(gid)
        if g is None:
            unknown = True
            continue
        for p in g.get("IpPermissions", []):
            any_rule = True
            open_ = any(r.get("CidrIp") == "0.0.0.0/0" for r in p.get("IpRanges", [])) or \
                    any(r.get("CidrIpv6") == "::/0" for r in p.get("Ipv6Ranges", []))
            if open_:
                lo = p.get("FromPort")
                ports.append("all" if lo in (None, -1) else str(lo))
    return ports, unknown, any_rule

rows = []
for e in sorted(enis, key=lambda x: x["NetworkInterfaceId"]):
    gids = [g["GroupId"] for g in e.get("Groups", [])]
    gnames = [(group(g) or {}).get("GroupName", g) for g in gids]
    pub = (e.get("Association") or {}).get("PublicIp")
    route = default_route(route_table(e.get("SubnetId")))
    ports, unknown, any_rule = internet_ingress(gids)
    att = (e.get("Attachment") or {}).get("InstanceId")
    orphan = (e.get("Status") == "available" and not e.get("Attachment")
              and not (e.get("Description") or "").startswith("ECS task")) \
             or (att is not None and state.get(att) == "terminated")

    if unknown and not ports:
        verdict = "UNKNOWN (a security group could not be read)"
    elif pub and route == "igw" and ports:
        verdict = "INTERNET-EXPOSED"
    elif pub and route == "igw":
        verdict = "PUBLIC-BUT-CLOSED" + ("" if any_rule else " (no ingress rule at all)")
    elif not pub and route == "nat":
        verdict = "PRIVATE-EGRESS"
    elif not pub and route == "none":
        verdict = "ISOLATED"
    elif not pub and route == "igw":
        # Public subnet, no public address: the internet has nothing to send to, even if a
        # group is open. One control (the address) holds everything up - say so.
        verdict = "NOT-ADDRESSABLE" + (" (open group, one control left)" if ports else "")
    else:
        verdict = f"REVIEW (public={bool(pub)}, route={route})"
    if orphan:
        verdict += " +ORPHAN"

    rows.append({
        "eni": e["NetworkInterfaceId"],
        "subnet": e.get("SubnetId"),
        "privateIp": e.get("PrivateIpAddress"),
        "publicIp": pub,
        "defaultRoute": route,
        "groups": gnames,
        "internetPorts": ports,
        "attachedTo": att or (e.get("Description") or "-")[:40],
        "verdict": verdict,
    })

print("== USMS exposure report  (routing + address + security groups) ==")
print()
for r in rows:
    print(f"  {r['eni']:<22} {r['privateIp'] or '-':<13} pub={r['publicIp'] or 'NONE':<10} "
          f"route={r['defaultRoute']:<5} open={','.join(r['internetPorts']) or '-':<8} "
          f"{','.join(r['groups']):<20} {r['verdict']}")
print()
counts = {}
for r in rows:
    k = r["verdict"].split(" ")[0]
    counts[k] = counts.get(k, 0) + 1
print("  " + "  ".join(f"{k}={v}" for k, v in sorted(counts.items())) + f"  interfaces={len(rows)}")

json.dump(rows, open(out_path, "w"), indent=2)
print(f"  written: outputs/lab-09-exposure.json")
PY
exit 0
