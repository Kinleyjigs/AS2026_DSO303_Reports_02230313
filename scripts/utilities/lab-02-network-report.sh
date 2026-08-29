#!/usr/bin/env bash
set -uo pipefail
# -e is intentionally omitted: when a subnet has no default route, the jq
# lookups below correctly return empty strings rather than erroring, and we
# want the loop to keep going and print "ISOLATED" for that subnet rather
# than have the whole script die on one subnet's missing route.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$REPO_ROOT/configs/course.env"
source "$REPO_ROOT/configs/lab-02.env"

VPC_ID="$USMS_VPC_ID"

# List every subnet in the VPC: id, CIDR, AZ, Name tag (order preserved via array query)
SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`]|[0].Value]' \
  --output text)

while IFS=$'\t' read -r subnet_id cidr az name; do
  [ -z "$subnet_id" ] && continue

  # Find the route table explicitly associated with this subnet
  rt_id=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$subnet_id" \
    --query 'RouteTables[0].RouteTableId' --output text)

  # No explicit association -> the VPC's main route table applies
  if [ "$rt_id" = "None" ] || [ -z "$rt_id" ]; then
    rt_id=$(aws ec2 describe-route-tables \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
      --query 'RouteTables[0].RouteTableId' --output text)
  fi

  # Pull the default route (0.0.0.0/0) target, if any
  default_route=$(aws ec2 describe-route-tables \
    --route-table-ids "$rt_id" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`]|[0]' \
    --output json)

  gw=$(echo "$default_route" | jq -r '.GatewayId // empty' 2>/dev/null)
  nat=$(echo "$default_route" | jq -r '.NatGatewayId // empty' 2>/dev/null)

  if [[ "$gw" == igw-* ]]; then
    printf "%-22s  %-12s  %-10s  %-8s via %s\n" "$name" "$cidr" "$az" "PUBLIC" "$gw"
  elif [[ "$nat" == nat-* ]]; then
    printf "%-22s  %-12s  %-10s  %-8s via %s\n" "$name" "$cidr" "$az" "PRIVATE" "$nat"
  else
    printf "%-22s  %-12s  %-10s  %-8s no default route\n" "$name" "$cidr" "$az" "ISOLATED"
  fi
done <<< "$SUBNETS"
