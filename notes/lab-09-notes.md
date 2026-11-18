# Lab 09 - Notes

- **Support path (Step 3):** **Path A (full).** Every probe was SUPPORTED except `iam get-credential-report`; even `simulate-principal-policy` worked.
- **Transcripts bucket at Step 6:** `usms-student-data` did **not** exist (`head-bucket` → 404, exit 254). Lab 10 creates it.

## Your Turn answers
**Step 4: two trust policies**
- `usms-ec2-app-role` trusts a **service** (`ec2.amazonaws.com`): whoever can launch an instance with its profile gets its permissions.
- `usms-developer-role` trusts **one user** (`usms-dev-01`): only that person, with their own key, can assume it.

**Step 6: actions needed**
- Enrolment API (display): `s3:ListBucket`, `s3:GetObject`.
- Registry upload (store): those two + `s3:PutObject`. The extra one is **`s3:PutObject`**.
- ListBucket lets the reader get 404 (missing) instead of 403 for a missing key.

**Step 11: usms-db-01**
- No instance profile → no credentials to serve → `--http-endpoint disabled`.
- On `usms-web-01` that would break its role credentials (no S3 or other AWS API calls).

**Step 17: if a control fails**
- Control 3 (route) fails: still no public IP, so the internet has no address; SG and NACL still block.
- Control 4 (SG) fails: still no public IP, no IGW route, and the private NACL filters the subnet.

## Section 14 - Review Questions

### 1. Why is "five verify scripts unchanged" a strong result?
- They were written **before** this lab, so they can't be biased towards it.
- They test what earlier labs promised (ALB, service, scaling, network), and all 5 matched the Step 2 baseline exactly.
- **Plausible break:** Step 13 revoking enrolment egress *before* authorising the new rules would, on real AWS, stop image pulls; a Lab 4/5 "service running" check would fail.
- Another: Exercise 4's "close the web front door" would break `verify-lab-03`'s ingress check.
- **What I'd do:** read the diff, decide if the change was intended, then update that check in the same commit (or roll back).

### 2. Boundary attached as a normal policy?
- As a **boundary** it only caps; it grants nothing.
- As an **attached policy** it **grants** its Allows: `ecs:*`, `elasticloadbalancing:*`, `s3:Get*`, `s3:PutObject`, `iam:PassRole` on `*`...
- **Both directions:**
  - **Up:** the role gains far more than `USMSDeployBase`.
  - **Down:** with no boundary left, nothing caps a future attached policy.
- **Dangerous** once someone also attaches any broad policy: `iam:PassRole` on `*` is back, which is the escalation path.
- **Caught by:** "the boundary is attached to NOTHING as an ordinary policy" and "usms-deploy-role HAS a permissions boundary".

### 3. Breach with every ingress rule correct
- **Incident:** a bug in the enrolment app (SSRF or code injection) lets an attacker run code in a task. Ingress was fine; the attacker came in through the *allowed* port 80 via the ALB.
- The task role has `USMSStudentDataReadWrite`, so the attacker reads every transcript and sends it out.
- **Steps 13–15 narrowed it:** no DNS tunnelling, no reverse shell on odd ports, no SSH or SMTP out. Only **HTTPS 443** remains.
- **Prevented entirely by:** least privilege (a read-only role, no Delete), plus **egress filtered by domain** (Network Firewall or a proxy), plus a bucket policy / VPC endpoint policy so data can't go to *another* bucket.
- **Not buildable here:** Floci has no Network Firewall, carries no traffic, and enforces no IAM.

### 4. If an attacker can call sts:AssumeRole from their own machine
- **`usms-ecs-task-role` / `usms-transcripts-reader-role`:** trust = `ecs-tasks.amazonaws.com` **service** + SourceAccount/SourceArn. An attacker's own user is not that principal → **denied**. Even another account's ECS is blocked by the conditions.
- **`usms-deploy-role`:** trusts **`user/usms-admin-01`**. If the attacker *has that user's keys*, they **get in**, but are capped by the boundary (no IAM changes, PassRole only for 3 roles to ECS).
- **Why different:** a service trust is about *who runs the workload*; a user trust is about *whose credentials you hold*. Stolen user keys beat a user trust; they don't beat a service trust.

### 5. Five controls vs one control
- The 5 controls on `usms-db-01` fail **independently** (address, subnet setting, route, SG, NACL); an attacker has to beat all of them.
- But they aren't "5× better": several share a failure mode (e.g. one admin with full EC2 rights can change them all at once).
- `usms-enrolment-sg` looks like "one control" only because the **matrix models SGs only**.
- The tasks also have **no public IP**, a **private subnet** and a **NAT-only route**, so they are about as well protected as the DB. The tool understates them.

### 6. The two extra rotation steps
- **Step 2 (move consumers before touching the old key):** prevents an **outage**: the profile always has a working key.
- **Step 3 (deactivate before delete):** prevents **irreversible breakage**. If a forgotten consumer still uses the old key, reactivate it instead of losing it forever.
- **Long-lived key = compromise:** it works from anywhere until someone notices, and keys leak (git, laptops, logs).
- **Real system:** humans → **IAM Identity Center / SSO** (short-lived sessions, MFA); workloads → **roles** (instance profiles, task roles, IRSA).

### 7. Is reading an adequate substitute for testing?
- **Reading catches:** things that *can* happen but haven't, e.g. `s3:Get*` on `*` for auditors, or `iam:PassRole` on `*`. A test only shows what one request did.
- **Testing catches:** what reading misses, e.g. a condition key the service never sends (a trust that silently denies everything) or a typo in an ARN.
- **Not a full substitute:** reading proves intent; testing proves behaviour.
- **For transcripts, reading first:** you can't test "nobody else can read it" by trying a few principals, and a missed reader is a breach. Then test on real AWS (Access Analyzer, simulate).
