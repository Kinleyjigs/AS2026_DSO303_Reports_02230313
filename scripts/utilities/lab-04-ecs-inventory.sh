#!/usr/bin/env bash
# Lab 04 Exercise 3 - ECS configuration drift report.
# One line per service in the cluster, plus the same data as JSON in outputs/.
#
# Why NOT set -e: this is a report. If one service or task definition fails to
# describe, the script should print an explicit "unknown"/"N/A" for that row and
# carry on with the rest, rather than aborting and hiding every other service.
# Each AWS call checks its own failure instead.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"
source "$REPO_ROOT/configs/lab-04.env" 2>/dev/null || true

CLUSTER="${USMS_ECS_CLUSTER:-usms-ecs-cluster}"
OUT_JSON="$REPO_ROOT/outputs/lab-04-ecs-inventory.json"
mkdir -p "$REPO_ROOT/outputs"

arns=$(aws ecs list-services --cluster "$CLUSTER" --query 'serviceArns[]' --output text) \
  || { echo "ERROR: cannot list services in $CLUSTER" >&2; exit 1; }

if [ -z "$arns" ] || [ "$arns" = "None" ]; then
  echo "No services in $CLUSTER"
  echo '{"cluster":"'"$CLUSTER"'","services":[]}' > "$OUT_JSON"
  exit 0
fi

records=()
for arn in $arns; do
  svc=$(aws ecs describe-services --cluster "$CLUSTER" --services "$arn" \
          --query 'services[0]' --output json 2>/dev/null) || svc='{}'

  name=$(jq -r '.serviceName // "unknown"' <<<"$svc")
  desired=$(jq -r '.desiredCount // "unknown"' <<<"$svc")
  running=$(jq -r '.runningCount // "unknown"' <<<"$svc")
  td_ref=$(jq -r '.taskDefinition // empty' <<<"$svc")
  pip_raw=$(jq -r '.networkConfiguration.awsvpcConfiguration.assignPublicIp // empty' <<<"$svc")

  # publicip verdict - computed from the setting, never from a name or tag
  case "$pip_raw" in
    ENABLED)  publicip=RISK ;;
    DISABLED) publicip=OK ;;
    *)        publicip=N/A ;;   # no networkConfiguration (e.g. EC2 launch type)
  esac

  # roles verdict - computed from the task definition the service points at
  td='{}'
  if [ -n "$td_ref" ]; then
    td=$(aws ecs describe-task-definition --task-definition "$td_ref" \
           --query 'taskDefinition' --output json 2>/dev/null) || td='{}'
  fi
  taskdef=$(jq -r 'if .family then "\(.family):\(.revision)" else "unknown" end' <<<"$td")
  exec_arn=$(jq -r '.executionRoleArn // empty' <<<"$td")
  task_arn=$(jq -r '.taskRoleArn // empty' <<<"$td")

  if [ -z "$exec_arn" ] || [ -z "$task_arn" ]; then roles=N/A
  elif [ "$exec_arn" = "$task_arn" ];            then roles=SAME
  else                                                 roles=SEPARATE
  fi

  printf '%-22s desired=%-3s running=%-3s taskdef=%-20s roles=%-9s publicip=%s\n' \
    "$name" "$desired" "$running" "$taskdef" "$roles" "$publicip"

  records+=("$(jq -n --arg s "$name" --arg d "$desired" --arg r "$running" \
      --arg t "$taskdef" --arg ro "$roles" --arg p "$publicip" \
      '{service:$s, desired:$d, running:$r, taskdef:$t, roles:$ro, publicip:$p}')")
done

printf '%s\n' "${records[@]}" \
  | jq -s --arg c "$CLUSTER" '{cluster:$c, services:.}' > "$OUT_JSON"
