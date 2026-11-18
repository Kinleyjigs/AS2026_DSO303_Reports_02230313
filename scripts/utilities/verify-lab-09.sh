#!/usr/bin/env bash
# Verify every Lab 09 control exists and is configured correctly.
# Read-only: this script inspects and changes nothing. Safe to run at any time.
# Exit 0 if every check passes, 1 otherwise.
#
# EXPECTED: PASS=50  FAIL=0
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env"
source "$REPO_ROOT/configs/lab-01.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-02.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-03.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-04.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-05.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-09.env" 2>/dev/null || true

# Defaults so that set -u cannot abort the script before it has told you anything.
: "${USMS_ACCOUNT_ID:=000000000000}"
: "${USMS_VPC_ID:=none}"
: "${USMS_APP_SG:=none}"
: "${USMS_DB_SG:=none}"
: "${USMS_ENROLMENT_SG:=none}"
: "${USMS_ALB_SG:=none}"
: "${USMS_BASTION_SG:=none}"
: "${USMS_PRIVATE_SUBNET_A:=none}"
: "${USMS_PRIVATE_RT:=none}"
: "${USMS_DEV_USER:=usms-dev-01}"
: "${USMS_INSTANCE_PROFILE:=usms-ec2-app-profile}"
: "${USMS_ECS_CLUSTER:=usms-ecs-cluster}"
: "${USMS_ENROLMENT_SERVICE:=usms-enrolment-svc}"
: "${USMS_ECS_TASK_ROLE:=usms-ecs-task-role}"
: "${USMS_WEB_INSTANCE:=none}"
: "${USMS_DB_INSTANCE:=none}"
: "${FLOCI_CONTAINER_NAME:=floci}"

PASS=0; FAIL=0
check() {
  if eval "$2" >/dev/null 2>&1; then printf "  ok   %s\n" "$1"; PASS=$((PASS+1))
  else printf "  FAIL %s\n" "$1"; FAIL=$((FAIL+1)); fi
}

# One policy document, by policy name, at its DEFAULT version.
poldoc() {
  local arn ver
  arn=$(aws iam list-policies --scope Local \
        --query "Policies[?PolicyName=='$1'].Arn | [0]" --output text 2>/dev/null)
  [ -n "$arn" ] && [ "$arn" != "None" ] || return 1
  ver=$(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null)
  aws iam get-policy-version --policy-arn "$arn" --version-id "$ver" \
    --query 'PolicyVersion.Document' --output json 2>/dev/null
}

# Does a policy document list ACTION under statements with EFFECT?  exit 0 = yes
has_action() {  # usage: poldoc X | has_action Allow s3:PutObject
  python3 -c '
import json, sys
eff, act = sys.argv[1], sys.argv[2]
d = json.load(sys.stdin)
sts = d["Statement"] if isinstance(d["Statement"], list) else [d["Statement"]]
acts = [x for s in sts if s["Effect"] == eff
          for x in (s["Action"] if isinstance(s["Action"], list) else [s["Action"]])]
sys.exit(0 if act in acts else 1)
' "$1" "$2"
}

# Exit 0 if no Allow statement grants iam:PassRole on Resource "*".
passrole_scoped() {
  python3 -c '
import json, sys
d = json.load(sys.stdin)
L = lambda x: x if isinstance(x, list) else [x]
bad = [s for s in L(d["Statement"]) if s["Effect"] == "Allow"
       and "iam:PassRole" in L(s["Action"]) and "*" in L(s["Resource"])]
sys.exit(1 if bad else 0)
'
}

# Egress rules on a group that are the AWS default allow-all shape.
allowall() {
  aws ec2 describe-security-groups --group-ids "$1" \
    --query 'length(SecurityGroups[0].IpPermissionsEgress[?IpProtocol==`-1`])' --output text 2>/dev/null
}

# Egress rules on a group whose port is not 443.
non443() {
  aws ec2 describe-security-groups --group-ids "$1" \
    --query 'length(SecurityGroups[0].IpPermissionsEgress[?FromPort!=`443`])' --output text 2>/dev/null
}

echo "== Environment =="
check "Floci container running" \
  "test \"\$(docker container inspect $FLOCI_CONTAINER_NAME --format '{{.State.Running}}')\" = true"
check "Storage mode is NOT memory" \
  "docker container inspect $FLOCI_CONTAINER_NAME --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -qE '^FLOCI_STORAGE_MODE=(hybrid|persistent|wal)$'"
check "AWS CLI reaches Floci" "aws sts get-caller-identity"
check "Account is 000000000000" \
  "test \"\$(aws sts get-caller-identity --query Account --output text)\" = 000000000000"

echo "== Labs 01 to 06 dependencies still present =="
check "usms-vpc exists" "aws ec2 describe-vpcs --vpc-ids $USMS_VPC_ID"
check "$USMS_ECS_TASK_ROLE exists" "aws iam get-role --role-name $USMS_ECS_TASK_ROLE"
check "$USMS_INSTANCE_PROFILE exists" \
  "aws iam get-instance-profile --instance-profile-name $USMS_INSTANCE_PROFILE"
check "$USMS_ENROLMENT_SERVICE is ACTIVE" \
  "test \"\$(aws ecs describe-services --cluster $USMS_ECS_CLUSTER --services $USMS_ENROLMENT_SERVICE --query 'services[0].status' --output text)\" = ACTIVE"
check "USMSStudentDataReadWrite is still on at least TWO roles (Lab 10 needs them)" \
  "test \"\$(aws iam list-entities-for-policy --policy-arn arn:aws:iam::$USMS_ACCOUNT_ID:policy/USMSStudentDataReadWrite --query 'length(PolicyRoles)' --output text)\" -ge 2"

echo "== Lab 09 identity: the read-only split =="
check "USMSStudentDataReadOnly exists" \
  "aws iam list-policies --scope Local --query \"Policies[?PolicyName=='USMSStudentDataReadOnly'].Arn | [0]\" --output text | grep -q '^arn:'"
check "it ALLOWS s3:GetObject" "poldoc USMSStudentDataReadOnly | has_action Allow s3:GetObject"
check "it does NOT allow s3:PutObject" "! poldoc USMSStudentDataReadOnly | has_action Allow s3:PutObject"
check "it explicitly DENIES s3:PutObject" "poldoc USMSStudentDataReadOnly | has_action Deny s3:PutObject"
check "usms-transcripts-reader-role exists" "aws iam get-role --role-name usms-transcripts-reader-role"
check "it carries USMSStudentDataReadOnly" \
  "aws iam list-attached-role-policies --role-name usms-transcripts-reader-role --query 'AttachedPolicies[].PolicyName' --output text | grep -q USMSStudentDataReadOnly"

echo "== Lab 09 identity: the confused-deputy fix =="
check "$USMS_ECS_TASK_ROLE trust policy has a Condition" \
  "test \"\$(aws iam get-role --role-name $USMS_ECS_TASK_ROLE --query 'length(Role.AssumeRolePolicyDocument.Statement[0].Condition)' --output text)\" -ge 1"
check "its principal is STILL ecs-tasks.amazonaws.com" \
  "aws iam get-role --role-name $USMS_ECS_TASK_ROLE --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Service' --output text | grep -q 'ecs-tasks.amazonaws.com'"
check "the condition pins aws:SourceAccount to this account" \
  "aws iam get-role --role-name $USMS_ECS_TASK_ROLE --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringEquals.\"aws:SourceAccount\"' --output text | grep -qx '$USMS_ACCOUNT_ID'"

echo "== Lab 09 identity: PassRole and the boundary =="
check "USMSDeployBase exists" \
  "aws iam list-policies --scope Local --query \"Policies[?PolicyName=='USMSDeployBase'].Arn | [0]\" --output text | grep -q '^arn:'"
check "its iam:PassRole names role ARNs, not Resource \"*\"" "poldoc USMSDeployBase | passrole_scoped"
check "its iam:PassRole carries an iam:PassedToService condition" \
  "poldoc USMSDeployBase | grep -q 'iam:PassedToService'"
check "USMSPermissionsBoundary exists" \
  "aws iam list-policies --scope Local --query \"Policies[?PolicyName=='USMSPermissionsBoundary'].Arn | [0]\" --output text | grep -q '^arn:'"
check "the boundary is attached to NOTHING as an ordinary policy" \
  "aws iam list-entities-for-policy --policy-arn arn:aws:iam::$USMS_ACCOUNT_ID:policy/USMSPermissionsBoundary && test -z \"\$(aws iam list-entities-for-policy --policy-arn arn:aws:iam::$USMS_ACCOUNT_ID:policy/USMSPermissionsBoundary --query '[PolicyRoles,PolicyUsers,PolicyGroups][]' --output text)\""
check "usms-deploy-role exists" "aws iam get-role --role-name usms-deploy-role"
check "usms-deploy-role HAS a permissions boundary" \
  "aws iam get-role --role-name usms-deploy-role --query 'Role.PermissionsBoundary.PermissionsBoundaryArn' --output text | grep -q 'USMSPermissionsBoundary'"
check "usms-deploy-role trusts a USER, not a service" \
  "aws iam get-role --role-name usms-deploy-role --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.AWS' --output text | grep -q ':user/'"

echo "== Lab 09 credentials and metadata =="
check "$USMS_DEV_USER has EXACTLY ONE access key" \
  "test \"\$(aws iam list-access-keys --user-name $USMS_DEV_USER --query 'length(AccessKeyMetadata)' --output text)\" = 1"
check "that key is Active" \
  "test \"\$(aws iam list-access-keys --user-name $USMS_DEV_USER --query 'AccessKeyMetadata[0].Status' --output text)\" = Active"
check "usms-web-01 requires IMDSv2" \
  "test \"\$(aws ec2 describe-instances --instance-ids $USMS_WEB_INSTANCE --query 'Reservations[0].Instances[0].MetadataOptions.HttpTokens' --output text)\" = required"

echo "== Lab 09 network: ingress unchanged =="
check "usms-alb-sg still admits tcp/80 from 0.0.0.0/0" \
  "aws ec2 describe-security-groups --group-ids $USMS_ALB_SG --query 'SecurityGroups[0].IpPermissions[?FromPort==\`80\`].IpRanges[].CidrIp' --output text | grep -q '0.0.0.0/0'"
check "usms-enrolment-sg still admits tcp/80 from usms-alb-sg" \
  "aws ec2 describe-security-groups --group-ids $USMS_ENROLMENT_SG --query 'SecurityGroups[0].IpPermissions[].UserIdGroupPairs[].GroupId' --output text | grep -qw $USMS_ALB_SG"
check "usms-db-sg still admits tcp/5432 from usms-app-sg" \
  "aws ec2 describe-security-groups --group-ids $USMS_DB_SG --query 'SecurityGroups[0].IpPermissions[].UserIdGroupPairs[].GroupId' --output text | grep -qw $USMS_APP_SG"

echo "== Lab 09 network: egress written =="
check "usms-alb-sg has NO allow-all egress rule" "test \"\$(allowall $USMS_ALB_SG)\" = 0"
check "usms-alb-sg egress destination is a GROUP, not a CIDR" \
  "aws ec2 describe-security-groups --group-ids $USMS_ALB_SG --query 'SecurityGroups[0].IpPermissionsEgress[].UserIdGroupPairs[].GroupId' --output text | grep -qw $USMS_ENROLMENT_SG"
check "usms-enrolment-sg has NO allow-all egress rule" "test \"\$(allowall $USMS_ENROLMENT_SG)\" = 0"
check "usms-enrolment-sg egress is tcp/443 only" "test \"\$(non443 $USMS_ENROLMENT_SG)\" = 0"
check "usms-db-sg has NO allow-all egress rule" "test \"\$(allowall $USMS_DB_SG)\" = 0"
check "usms-db-sg egress is tcp/443 only" "test \"\$(non443 $USMS_DB_SG)\" = 0"

echo "== Lab 09 network: the SSH cutover =="
check "usms-bastion-sg exists" \
  "aws ec2 describe-security-groups --filters Name=group-name,Values=usms-bastion-sg Name=vpc-id,Values=$USMS_VPC_ID --query 'SecurityGroups[0].GroupId' --output text | grep -q '^sg-'"
check "usms-app-sg admits tcp/22 from a GROUP" \
  "aws ec2 describe-security-groups --group-ids $USMS_APP_SG --query 'SecurityGroups[0].IpPermissions[?FromPort==\`22\`].UserIdGroupPairs[].GroupId' --output text | grep -q '^sg-'"
check "usms-app-sg has NO CIDR source on tcp/22" \
  "test \"\$(aws ec2 describe-security-groups --group-ids $USMS_APP_SG --query 'length(SecurityGroups[0].IpPermissions[?FromPort==\`22\`].IpRanges[])' --output text)\" = 0"

echo "== The negatives that must stay true =="
check "usms-db-01 has NO public address" \
  "test \"\$(aws ec2 describe-instances --instance-ids $USMS_DB_INSTANCE --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)\" = None"
check "the private subnet does NOT auto-assign public addresses" \
  "test \"\$(aws ec2 describe-subnets --subnet-ids $USMS_PRIVATE_SUBNET_A --query 'Subnets[0].MapPublicIpOnLaunch' --output text)\" = False"
check "the private route table has NO internet gateway route" \
  "aws ec2 describe-route-tables --route-table-ids $USMS_PRIVATE_RT && ! aws ec2 describe-route-tables --route-table-ids $USMS_PRIVATE_RT --query 'RouteTables[0].Routes[].GatewayId' --output text | grep -q 'igw-'"

echo "== Files, documents and Git hygiene =="
check "configs/lab-09.env exists" "test -f configs/lab-09.env"
check "configs/lab-09.env has no empty values" \
  "! grep -qE 'export [A-Z_0-9]+=\$|=None\$' configs/lab-09.env"
check "every policies/ document is valid JSON" \
  "for f in policies/*.json; do python3 -m json.tool \"\$f\" >/dev/null || exit 1; done"
# Shell variables (${USMS_...}, $FOO) must have been expanded. IAM policy variables
# such as ${aws:username} (Lab 01) are meant to stay, so they are not counted.
check "no policies/ document contains an unexpanded shell variable" \
  "! grep -lE '\\\$\\{?[A-Z_]' policies/*.json"
check "the three audit scripts exist and are executable" \
  "test -x scripts/utilities/usms-iam-audit.sh && test -x scripts/utilities/usms-sg-audit.sh && test -x scripts/utilities/usms-reachability-matrix.sh"
# outputs/.gitkeep is tracked on purpose; any OTHER file under outputs/ is a leak.
check "no secret is tracked by git" "! git ls-files outputs/ | grep -qv '^outputs/.gitkeep$'"

echo; echo "PASS=$PASS  FAIL=$FAIL"
if [ "$FAIL" -ne 0 ]; then
cat <<'REMEDY'

A failure under "== Environment ==" is the real problem, and most failures below it are
a consequence. Fix that block first:
    ./scripts/utilities/floci-storage-check.sh
A failure under "== Labs 01 to 06 dependencies ==" means an earlier lab's resource is
gone. Run verify-lab-02.sh to verify-lab-06.sh before re-reading anything here.
A failure under "== The negatives that must stay true ==" is the most serious kind in
this script: something that was unreachable has become reachable. Stop and find out
what changed before doing anything else.
REMEDY
fi
[ "$FAIL" -eq 0 ]
