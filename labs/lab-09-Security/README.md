# Lab 09: Securing the USMS Application with IAM Roles and Security Groups

## 1. Objectives
- Review the USMS system (Labs 1–6) on both access-control axes: **IAM** (who can call what) and **security groups** (what can reach what).
- Inventory and audit every role and security group with read-only scripts.
- Fix identity findings: read-only transcripts policy, confused-deputy trust conditions, scoped `iam:PassRole`, permissions boundary, session policy, access key rotation, IMDSv2.
- Fix network findings: written egress on three groups, SSH only from a bastion group, and prove the data tier is unreachable.
- Prove every control survives a restart and no earlier lab broke; save results to `configs/lab-09.env`.

## 2. Prerequisites
- Labs 1–6 complete, Floci running under Docker Compose with `FLOCI_STORAGE_MODE=hybrid`.
- `jq`, `python3`, AWS CLI v2, and the `usms-dev` profile working.
- Env files `course.env` and `lab-01.env` to `lab-06.env` sourced in one terminal.

## 7. Step-by-Step Implementation

### Step 1 - Resume the environment and load the env files
![alt text](<../../screenshots/Lab 9 screenshots/1.png>)

*Figure 1: Lab 1–6 env values loaded. All 17 values are non-empty.*

- On this setup the role variables (e.g. `USMS_ROLE_EC2`) hold full **ARNs**, not names, so later steps used `${VAR##*/}` or the ARN directly.

### Step 2 - Record the security baseline
![alt text](<../../screenshots/Lab 9 screenshots/2.png>)

*Figure 2: Baseline from verify-lab-02 to 06, saved to `outputs/lab-09-pre-verify.txt` before any change.*

First run had extra failures. Fixed before recording:
- `usms-web-01` was **stopped** (Floci stops instances on restart) → started it.
- `USMS_ALB_LISTENER_ARN` was **empty** in `configs/lab-05.env` → filled from `describe-listeners`.

Known failures left in the baseline:
| Lab | FAIL | Reason |
|---|---|---|
| 02, 05 | 1 | "no secret is tracked by git" matches `outputs/.gitkeep` (false positive) |
| 04 | 2 | `.gitkeep` + the documented Lab 5 `usms-app-sg` source check |
| 06 | 4 | `.gitkeep` + 3 scheduled-action checks: Floci 2.4.0 says `DescribeScheduledActions is not supported` |

- `tail -1` printed help text for failing scripts, so `grep '^PASS='` was used instead.

### Step 3 - Probe what this Floci build supports
![alt text](<../../screenshots/Lab 9 screenshots/3.png>)

*Figure 3: Support probe. Every IAM and EC2 call is SUPPORTED except `get-credential-report`.*

- **Path A (full):** even `simulate-principal-policy` and `get-account-authorization-details` work.
- Only `iam get-credential-report` is not available.

### Step 4 - Inventory every identity
![alt text](<../../screenshots/Lab 9 screenshots/4.png>)

*Figure 4: Roles, users with their access key counts, and customer managed policies.*

![alt text](<../../screenshots/Lab 9 screenshots/5.png>)

*Figure 5: Machine-readable inventory: 8 roles, none with a permissions boundary.*

- 8 roles (PDF shows 5): extra are the auto scaling service-linked role and 2 EKS roles from Labs 7/8.
- Every role: `boundary=-`.

#### Your Turn - two trust policies
![alt text](<../../screenshots/Lab 9 screenshots/7.png>)

*Figure 6: Trust policies of usms-ec2-app-role and usms-developer-role side by side.*

- `usms-ec2-app-role` trusts a **service** (`ec2.amazonaws.com`): anyone who can launch an instance with its profile (via `iam:PassRole`) gets its permissions.
- `usms-developer-role` trusts **one IAM user** (`usms-dev-01`): only that person can assume it, with their own key; the risk is that key being stolen.

### Step 5 - Build the IAM audit script
![alt text](<../../screenshots/Lab 9 screenshots/6.png>)

*Figure 7: `usms-iam-audit.sh` findings: HIGH=7 MED=30 roles=8, exit code 1.*

- Script: `scripts/utilities/usms-iam-audit.sh` (read-only, exits 1 on HIGH).
- 4 checks: wildcard actions, `Resource "*"` on writes, unscoped `iam:PassRole`, service trust with no `Condition`.
- HIGH findings = **confused deputy** (service principal, no Condition) on every service role.
- MED = no permissions boundary on any role.
- Higher counts than the PDF (4/5) because of the extra roles.

### Step 6 - Read the transcripts policy
![alt text](<../../screenshots/Lab 9 screenshots/8.png>)

*Figure 8: USMSStudentDataReadWrite (ListBucket, Get+Put, Deny DeleteBucket) and the roles that carry it. The transcripts bucket does not exist yet (404).*

- Carried by **3 roles**: `usms-ec2-app-role`, `usms-ecs-task-role`, `usms-eks-node-role`.
- **Finding:** `s3:PutObject` is given to workloads that only read.
- `head-bucket` → 404 (exit 254). Expected: Lab 10 creates the bucket. A policy is about ARNs, so it can be reviewed before the bucket exists.

#### Your Turn - actions needed
- **Enrolment API (display):** `s3:ListBucket`, `s3:GetObject`.
- **Registry upload (store):** `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`.
- **Extra action:** `s3:PutObject`.
- Why ListBucket: without it S3 returns **403** for a missing key instead of **404**.

### Step 7 - Read-only policy and the role that carries it
![alt text](<../../screenshots/Lab 9 screenshots/9.png>)

*Figure 9: New usms-transcripts-reader-role with USMSStudentDataReadOnly, and usms-ecs-task-role trust scoped: SAME PRINCIPAL, NEW CONDITION.*

- `USMSStudentDataReadOnly`: List + Get, **explicit Deny** on Put/Delete/DeleteBucket/PutBucketPolicy.
  - The Deny adds nothing today, but still wins if a broader policy is attached later.
- New role `usms-transcripts-reader-role` with the scoped trust.
- `usms-ecs-task-role` trust rewritten (permissions untouched, Lab 10 needs them):
  - `aws:SourceAccount = 000000000000`
  - `aws:SourceArn like arn:aws:ecs:us-east-1:000000000000:*`
- Undo saved first: `outputs/lab-09-ecs-task-role-trust-before.json`.
- `usms-ec2-app-role` stays unconditioned: EC2 does not send `aws:SourceArn` for instance profiles.

### Step 8 - Scope iam:PassRole and add a permissions boundary
![alt text](<../../screenshots/Lab 9 screenshots/10.png>)

*Figure 10: usms-deploy-role with the USMSPermissionsBoundary boundary; iam:PassRole limited to 3 named roles; the boundary is attached to nothing.*

- `USMSPermissionsBoundary`: a **ceiling**, grants nothing. Denies all identity changes (CreateUser, AttachRolePolicy, DeleteRolePermissionsBoundary, ...) and deleting the network.
- `USMSDeployBase`: `iam:PassRole` only on `usms-ecs-exec-role`, `usms-ecs-task-role`, `usms-transcripts-reader-role`, only to `ecs-tasks.amazonaws.com`; explicit **Deny** on passing anything to EC2.
- `usms-deploy-role`: trusts only `user/usms-admin-01`, boundary stored (not null).
- Boundary attached to nothing (`[]`) is correct. **Do not delete it as an orphan.**
- Effective = identity policy ∩ boundary.

### Step 9 - Session policy and the intersection
![alt text](<../../screenshots/Lab 9 screenshots/11.png>)

*Figure 11: simulate-principal-policy as a second opinion: ec2:DescribeVpcs allowed, s3:GetObject implicitDeny, iam:CreateUser explicitDeny.*

- Assumed `usms-developer-role` with a session policy (Describe VPCs/Subnets/SGs only), 900 s.
- `USMSDeveloperBase` already allows `sts:GetCallerIdentity` and `s3:List*`, so **`s3:GetObject`** was used as the "not in identity policy" action.
- Python intersection: 3 Describe actions **ALLOWED**, `s3:GetObject` **denied** (a session policy cannot add permissions).
- Used **both** the Python fallback and `simulate-principal-policy` (Path A).
- Unset the session env vars afterwards; `whoami` back to root.

### Step 10 - Rotate the access key
![alt text](<../../screenshots/Lab 9 screenshots/12.png>)

*Figure 12: Rotation result. The usms-dev profile works on the new key, and only one key (created today) remains.*

- Order: **create → move profile → deactivate → delete**. Deactivate is the reversible safety step.
- New key written straight to `outputs/usms-dev-01-access-key-new.json` (chmod 600, git-ignored). The secret never appeared on screen.
- `usms-dev` profile repointed and verified: `user/usms-dev-01`.
- **What happened:** after `create-access-key`, Floci listed **only the new key**, so `OLD_KEY_ID` was `None` and deactivate/delete failed (`Invalid length ... value: 4`).
- End state is still correct: **1 active key, created today**, and the profile works.
- Real AWS: wait days between deactivate and delete; this lab compresses that pause.
- Better on real AWS: IAM Identity Center or federation for humans, roles for workloads, so no long-lived key.

### Step 11 - Require IMDSv2 on the web instance
![alt text](<../../screenshots/Lab 9 screenshots/13.png>)

*Figure 13: usms-web-01 metadata options: HttpTokens optional → required, hop limit 1.*

- `--http-tokens required`: stops **SSRF**. An attacker can make the app send a GET, but not the PUT with a header that gets a token.
- `--http-put-response-hop-limit 1`: stops a **container** on the host from getting the host role's credentials.
- Rollout order: check `MetadataNoToken` metric = 0 → update old SDKs → require tokens.
- Floci stores the option but serves no metadata service.

#### Your Turn - usms-db-01
- `usms-db-01` has **no instance profile**, so it has no credentials to serve → `--http-endpoint disabled`.
- Doing the same on `usms-web-01` would break its role credentials, so the app could not call S3 or other AWS APIs.

### Step 12 - Security group audit script
![alt text](<../../screenshots/Lab 9 screenshots/15.png>)

*Figure 14: `usms-sg-audit.sh` before hardening: HIGH=3 MED=10 LOW=5, 8 groups.*

- Script: `scripts/utilities/usms-sg-audit.sh`: findings from rules, not names.
- 8 groups (PDF shows 5): 3 extra EKS groups from Labs 7/8.
- `usms-alb-sg` shows 0 interfaces: Floci does not model ALB network interfaces.

| Finding | Verdict |
|---|---|
| `alb-sg` 80 from `0.0.0.0/0` | Accepted: internet-facing load balancer (Lab 5) |
| `app-sg` 80/443 from `0.0.0.0/0` | Open finding: a second internet entry point (Exercise 4) |
| `app-sg` 22 from `10.0.0.0/16` | Fixed in Step 16 |
| Default allow-all egress | Fixed in Steps 13–15 |
| `default` and EKS groups, no interfaces | Accepted, unused |

### Step 13 - Egress for the enrolment tasks
![alt text](<../../screenshots/Lab 9 screenshots/16.png>)

*Figure 15: usms-enrolment-sg: ingress tcp/80 from usms-alb-sg only; egress tcp/443 to the S3 prefix list pl-63a5400a and tcp/443 to 0.0.0.0/0. No allow-all.*

- Tasks only need: image pull, CloudWatch Logs, S3, so tcp/443 only.
- S3 via the Lab 2 gateway endpoint prefix list `pl-63a5400a`.
- Undo written first: `policies/usms-egress-allow-all.json`.
- Order: **authorise new rule first, then revoke default**, so there is no gap.
- Blocks DNS exfiltration, SSH, DB ports, SMTP, random C2 ports.
- **Floci bug:** after the revoke, `describe-security-group-rules` still listed the `-1` rule, while `describe-security-groups` did not. Verified with `describe-security-groups`.

### Step 14 - Load balancer egress to a security group
![alt text](<../../screenshots/Lab 9 screenshots/17.png>)

*Figure 16: usms-alb-sg: in tcp/80 from 0.0.0.0/0; out tcp/80 to usms-enrolment-sg only (CIDR null).*

- Targets' IPs change with every deploy/scale, so the rule names the **group**, not addresses.
- Lab 6 scaling does not change this rule.

### Step 15 - Data tier egress
![alt text](<../../screenshots/Lab 9 screenshots/18.png>)

*Figure 17: Allow-all egress left on usms-enrolment-sg, usms-alb-sg and usms-db-sg: 0 each.*

- `usms-db-sg`: tcp/443 out only (OS updates through `usms-nat`).
- Still a gap: HTTPS POST to anywhere is possible. Closing it needs hostname filtering (Network Firewall or a proxy).
- DNS (UDP/TCP 53 to `10.0.0.2`) left out because Floci has no resolver; on real AWS `dnf update` would fail without it (Exercise 1).

### Step 16 - SSH only from a bastion group
![alt text](<../../screenshots/Lab 9 screenshots/19.png>)

*Figure 18: usms-app-sg ingress: 80 and 443 from 0.0.0.0/0, and 22 only from usms-bastion-sg (sg-eeb1fb9c90792836c).*

- `usms-bastion-sg` did not exist → created (SSH in from `203.0.113.10/32`, a documentation address).
- New rule added first, then the `10.0.0.0/16` rule removed by **rule ID** (removes exactly one rule).
- A compromised Fargate task can no longer reach SSH on the web tier.

### Step 17 - Reachability matrix and proving a negative
![alt text](<../../screenshots/Lab 9 screenshots/20.png>)

*Figure 19: Reachability matrix: what each group may initiate, which instances have a public address, and the single-point-of-control groups.*

![alt text](<../../screenshots/Lab 9 screenshots/21.png>)

*Figure 20: Five independent controls proving usms-db-01 is unreachable from the internet.*

- Script: `scripts/utilities/usms-reachability-matrix.sh`.
- Internet reaches only `usms-alb-sg` (80) and `usms-app-sg` (80, 443).
- `usms-db-sg` ← only `usms-app-sg`; `usms-enrolment-sg` ← only `usms-alb-sg`.
- 7 groups are a **single point of control** (one ingress rule each): one mistake there = no protection.
- `public=127.0.0.1` on web instances is Floci's placeholder, not a real public IP.

| Control on usms-db-01 | Result |
|---|---|
| 1 No public IP | `None` |
| 2 Subnet no auto-assign | `False` |
| 3 No IGW route | NAT only (`nat-d574...`) |
| 4 SG admits one group | 5432 from `usms-app-sg`, no CIDR |
| 5 Custom NACL | `acl-2da6...`, not default |

#### Your Turn (Review Question 5)
- **If control 3 failed:** still no public IP (1, 2), so the internet has no address to send to; the SG and NACL still block it.
- **If control 4 failed:** still no public IP, no IGW route, and the private NACL filters the subnet.

### Step 18 - Restart, then prove nothing broke
![alt text](<../../screenshots/Lab 9 screenshots/22.png>)

*Figure 21: After a Floci stop/start, all 9 security facts are unchanged: PERSISTENCE PROVEN.*

![alt text](<../../screenshots/Lab 9 screenshots/23.png>)

*Figure 22: verify-lab-02 to 06 give the same results as the Step 2 baseline: NOTHING BROKE.*

- 9 facts re-read with every ID re-derived from the API (`outputs/lab-09-facts.sh`).
- After restart `usms-web-01` was stopped again → started before re-verifying.
- `NOTHING BROKE` = earlier labs unchanged; it does not prove this lab's changes are correct.

### Step 19 - Write configs/lab-09.env
![alt text](<../../screenshots/Lab 9 screenshots/24.png>)

*Figure 23: `configs/lab-09.env`: 16 exports, names and ARNs only, no secrets.*

- `USMS_IMDS_TOKENS=required`, `USMS_EGRESS_ALLOW_ALL_REMAINING=0`, `USMS_S3_PREFIX_LIST=pl-63a5400a`.
- Access key ID deliberately **not** stored; only the rotation date.
- First version read `optional`: the `usms-web-01` tag also matches an old **terminated** instance. Fixed with an `instance-state-name` filter.

## 8. Verification
![alt text](<../../screenshots/Lab 9 screenshots/25.png>)

*Figure 24: verify-lab-09.sh reports PASS=50 FAIL=0.*

- `scripts/utilities/verify-lab-09.sh`: 50 read-only checks (identity, credentials, egress, SSH, the negatives, files and git hygiene).
- Changes from the PDF version:
  - SG queries needed `SecurityGroups[0]`, or they returned nothing.
  - Boundary check reads `list-entities-for-policy` and expects an empty list.
  - "Unexpanded variable" check flags only shell-style `${USMS_...}`; Lab 1's `${aws:username}` is an IAM policy variable and is correct.
  - "No secret tracked" ignores `outputs/.gitkeep` (same fix as Lab 8); any real file under `outputs/` still fails.
- `scripts/cleanup/lab-09-cleanup.sh`: written, `bash -n` OK, **not run**.
  - Asks you to type `UNDO USMS SECURITY REVIEW`.
  - Deletes the Lab 9 roles and policies, restores the allow-all egress and the old SSH rule, removes the `app-sg` rule naming the bastion SG, then deletes `usms-bastion-sg`.
  - Does **not** undo the key rotation or IMDSv2: a cleanup should never make the account less secure.

## Floci vs Real AWS (what I saw)
| Feature | Real AWS | On Floci | Status |
| --- | --- | --- | --- |
| IAM policies, boundaries, session policies | Enforced on every call | Stored, never enforced | Proved by reading |
| `simulate-principal-policy` | Evaluates policies | Supported; gave allowed / implicitDeny / explicitDeny | Observed |
| `get-credential-report` | Available | Not available | Floci limitation |
| Access key rotation | Old key stays until deleted | Only new key listed after create | Floci quirk |
| IMDSv2 | Enforced at the hypervisor | Option stored, no metadata service | Partly observed |
| Security groups | Checked on every packet | Rules stored, no traffic | Proved by reading |
| Revoke egress rule | Gone from both APIs | `describe-security-group-rules` kept a stale rule | Floci bug |
| ALB network interfaces | Exist in subnets | 0 interfaces | Floci limitation |
| Scheduled scaling actions (Lab 6) | Supported | `DescribeScheduledActions` not supported | Floci limitation |
| Restart | n/a | Instances stopped after Floci restart | Floci behaviour |

## Analysis
I learned that IAM controls whether an API request is allowed, while routing, security groups and NACLs control network traffic. Both must allow the request for it to work. I also learned that service trust policies need proper conditions to prevent unwanted access and that `iam:PassRole` should be limited to specific roles and services. Permission boundaries and session policies help reduce permissions, while security groups should have clear outgoing rules to control network traffic. I also understood that multiple security checks are needed to prove that a database is unreachable. Since Floci does not automatically enforce these security rules, I checked the configurations manually and saved the checks in scripts.


