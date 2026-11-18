#!/usr/bin/env bash
# USMS transcripts bucket policy - DRAFT (Lab 09 Exercise 5).
#
# Reads the identity inventory and the three transcripts policy documents in policies/, finds
# every role granted any s3: action on the transcripts bucket, and writes:
#   outputs/lab-09-bucket-policy-draft.json   the resource policy the S3 configuration lab will apply
#   outputs/lab-09-lab10-readiness.txt        a one-page hand-off for Lab 10
# Applies NOTHING. Works whether or not the bucket exists. Reads only policy documents.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
# shellcheck disable=SC1090
source configs/course.env 2>/dev/null || true
ACCOUNT="${USMS_ACCOUNT_ID:-000000000000}"

INVENTORY="outputs/lab-09-identity-inventory.json"
POLICY_FILES=(policies/usms-student-data-rw-policy.json
              policies/usms-student-data-ro-policy.json
              policies/usms-lambda-basic-policy.json)
for f in "$INVENTORY" "${POLICY_FILES[@]}"; do
  [ -f "$f" ] || { echo "missing $f" >&2; exit 2; }
done

# The bucket name comes from Lab 01's policy document, never from typing it.
BUCKET_ARN=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for s in d["Statement"]:
    acts = s["Action"] if isinstance(s["Action"], list) else [s["Action"]]
    if "s3:ListBucket" in acts:
        r = s["Resource"]
        print(r if isinstance(r, str) else r[0]); break
' "${POLICY_FILES[0]}")
# Shell parameter expansion: strip the fixed ARN prefix to get the bare bucket name, without
# spawning sed/cut and without any chance of a regex surprise in the name.
BUCKET="${BUCKET_ARN#arn:aws:s3:::}"
[ -n "$BUCKET" ] && [ "$BUCKET" != "$BUCKET_ARN" ] || { echo "cannot derive bucket name" >&2; exit 2; }

DRAFT="outputs/lab-09-bucket-policy-draft.json"
READY="outputs/lab-09-lab10-readiness.txt"

python3 - "$INVENTORY" "$BUCKET" "$ACCOUNT" "$DRAFT" "$READY" "${POLICY_FILES[@]}" << 'PY'
import json, sys
inv_path, bucket, account, draft_path, ready_path, *policy_files = sys.argv[1:]
bucket_arn, objects_arn = f"arn:aws:s3:::{bucket}", f"arn:aws:s3:::{bucket}/*"
root = f"arn:aws:iam::{account}:root"
L = lambda x: x if isinstance(x, list) else [x]

def bucket_grants(doc):
    """(action, resource) pairs an Allow statement grants on this bucket."""
    out = set()
    for s in L((doc or {}).get("Statement")):
        if s.get("Effect") != "Allow":
            continue
        for a in L(s.get("Action")):
            if not a.lower().startswith("s3:"):
                continue
            for r in L(s.get("Resource")):
                if r in (bucket_arn, objects_arn):
                    out.add((a, r))
    return out

# The three transcripts policies, by name, as written in policies/.
policy_names = {"usms-student-data-rw-policy.json": "USMSStudentDataReadWrite",
                "usms-student-data-ro-policy.json": "USMSStudentDataReadOnly",
                "usms-lambda-basic-policy.json":    "USMSLambdaBasic"}
names = [policy_names[p.split("/")[-1]] for p in policy_files]

# Every role whose attached policy grants an s3: action on the bucket, with exactly those actions.
grants = {}
for role in json.load(open(inv_path)):
    for p in role.get("attachedPolicies", []) + role.get("inlinePolicies", []):
        g = bucket_grants(p.get("document"))
        if g:
            grants.setdefault(role["arn"], {"role": role["role"], "via": set(), "grants": set()})
            grants[role["arn"]]["via"].add(p["name"])
            grants[role["arn"]]["grants"] |= g

statements = []
for arn in sorted(grants):
    info = grants[arn]
    by_res = {}
    for a, r in info["grants"]:
        by_res.setdefault(r, set()).add(a)
    for r in (bucket_arn, objects_arn):
        if r in by_res:
            sid = info["role"].replace("-", " ").title().replace(" ", "") + ("Bucket" if r == bucket_arn else "Objects")
            statements.append({"Sid": f"Allow{sid}", "Effect": "Allow",
                               "Principal": {"AWS": arn},
                               "Action": sorted(by_res[r]), "Resource": r})

statements.append({"Sid": "DenyInsecureTransport", "Effect": "Deny", "Principal": "*",
                   "Action": "s3:*", "Resource": [bucket_arn, objects_arn],
                   "Condition": {"Bool": {"aws:SecureTransport": "false"}}})
statements.append({"Sid": "DenyEveryoneExceptTheNamedRolesAndRoot", "Effect": "Deny",
                   "NotPrincipal": {"AWS": sorted(grants) + [root]},
                   "Action": "s3:*", "Resource": [bucket_arn, objects_arn]})

policy = {"Version": "2012-10-17", "Id": "usms-transcripts-bucket-policy-DRAFT", "Statement": statements}
json.dump(policy, open(draft_path, "w"), indent=2)

with open(ready_path, "w") as f:
    f.write(f"bucket name (from {policy_files[0]}): {bucket}\n")
    f.write(f"transcripts policies:                 {', '.join(names)}\n")
    for arn in sorted(grants):
        g = grants[arn]
        f.write(f"role:                                 {arn}  via {', '.join(sorted(g['via']))}"
                f"  actions {', '.join(sorted({a for a, _ in g['grants']}))}\n")
    f.write(f"principal count (roles, excl. root):  {len(grants)}\n")
    f.write("when Lab 10 runs create-bucket:        nothing changes for these roles at first - their identity "
            "policies start to match a real bucket, and only when the S3 configuration lab applies this draft "
            "does every OTHER principal (and any non-TLS request) get an explicit Deny.\n")
print(f"draft:     {draft_path}  ({len(statements)} statements, {len(grants)} roles)")
print(f"readiness: {ready_path}")
PY

# ---- mechanical checks on the draft ----
python3 -m json.tool "$DRAFT" > /dev/null && echo "valid JSON"
python3 - "$DRAFT" "$BUCKET" << 'PY'
import json, sys
d, bucket = json.load(open(sys.argv[1])), sys.argv[2]
ok = True
for s in d["Statement"]:
    p = s.get("Principal", s.get("NotPrincipal"))
    if p == "*":
        if s["Sid"] != "DenyInsecureTransport":
            print(f"  FAIL {s['Sid']}: Principal \"*\""); ok = False
        continue
    arns = p["AWS"] if isinstance(p["AWS"], list) else [p["AWS"]]
    if not all(a.startswith("arn:aws:iam::") for a in arns):
        print(f"  FAIL {s['Sid']}: a principal is not an ARN"); ok = False
text = json.dumps(d)
both = f'"arn:aws:s3:::{bucket}"' in text and f'"arn:aws:s3:::{bucket}/*"' in text
print("every Principal is an ARN, except the insecure-transport Deny" if ok else "principal check FAILED")
print("bucket ARN present with and without /*" if both else "bucket ARN check FAILED")
PY
