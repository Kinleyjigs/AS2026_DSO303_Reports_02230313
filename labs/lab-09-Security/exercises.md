# Lab 09: Exercises

### Exercise 1 - Egress for the web tier
![alt text](<../../screenshots/Lab 9 screenshots/26.png>)

*Figure 1: usms-app-sg now has 6 written egress rules and no default rule; verify-lab-09 is still PASS=50 FAIL=0.*

| Need | Rule |
|---|---|
| S3 | tcp/443 → S3 prefix list |
| AWS APIs (STS) | tcp/443 → `0.0.0.0/0` |
| Enrolment API | tcp/80 → `usms-alb-sg` |
| Database | tcp/5432 → `usms-db-sg` |
| DNS | udp + tcp/53 → `10.0.0.2` |

- Unquoted heredoc, so the SG IDs are filled in.
- DNS: UDP first, TCP for large answers.
- IMDS (`169.254.169.254`) needs no rule: SGs don't filter it.
- Bastion egress should be only tcp/22 → `usms-app-sg`.

### Exercise 2 - Break-glass role
![alt text](<../../screenshots/Lab 9 screenshots/27.png>)

*Figure 2: Break-glass role with MFA + ExternalId, 1-hour session and a boundary. IAM audit: HIGH=0, 4 ACCEPTED.*

- **usms-breakglass-role:** only `usms-admin-01`, MFA **and** ExternalId, 1-hour session, boundary, only the 2 scaling calls from Lab 6.
- **Fixed:** exec role and Lambda role trust (added SourceAccount + SourceArn).
- **Accepted (with reason):** EC2 and EKS roles (EC2 can't send these keys), the service-linked role (AWS locks it).
- Accepted list: `configs/usms-iam-accepted-findings.tsv`. The audit shows them as `ACCEPTED`.

### Exercise 3 - Exposure report
![alt text](<../../screenshots/Lab 9 screenshots/28.png>)

*Figure 3: Same output from two folders. 16 interfaces classified by route, public IP and SG.*

| Verdict | Example |
|---|---|
| INTERNET-EXPOSED | `usms-web-01` |
| NOT-ADDRESSABLE (no public IP) | `usms-web-02` |
| PUBLIC-BUT-CLOSED | NAT gateway |
| PRIVATE-EGRESS | tasks, DB |
| UNKNOWN (SG deleted) | 2 old task interfaces |

- Public with no ingress rule = "closed today", not safe: one rule away from exposure.
- No `set -e`: one failed call should not stop the report.

### Exercise 4 - Security review
![alt text](<../../screenshots/Lab 9 screenshots/29.png>)

*Figure 4: Who can read transcripts: 3 roles read/write, 2 roles read, and usms-audit-01 through its group.*

**1. Web server (second front door)**
- `usms-web-01` is open on 80/443 to the internet, older than the ALB.
- Should move behind the ALB. Breaks direct IP access and needs an HTTPS listener.

**2. Egress control**
- **Stops:** DNS tunnelling, reverse shells on odd ports, SSH/SMTP out.
- **Doesn't stop:** data sent out over HTTPS (needs Network Firewall), or copying to another S3 bucket (needs endpoint/bucket policy).

**3. Who can read transcripts**

| Principal | Access |
|---|---|
| ec2-app, ecs-task, eks-node roles | Read + Write + Delete |
| transcripts-reader, lambda-exec roles | Read |
| `usms-audit-01` (auditors group) | **Read, unplanned** |

- Real AWS checks this with IAM Access Analyzer. Floci can't, so I read every policy and group.

**4. Detection**
- CloudTrail (free), GuardDuty, AWS Config, Access Analyzer, VPC Flow Logs.
- After an incident: CloudTrail → GuardDuty → Flow Logs → S3 logs.

**5. Move web behind the ALB (not run)**
1. Create target group `usms-web-tg`.
2. Register `usms-web-01`.
3. Add a listener rule on the ALB.
4. Allow app-sg port 80 from alb-sg.
5. Allow alb-sg egress to app-sg.
6. Check target health.
7. ⚠️ Remove 80/443 from `0.0.0.0/0` on app-sg (reversible; breaks direct access and verify-lab-03).

### Exercise 5 - Bucket policy draft
![alt text](<../../screenshots/Lab 9 screenshots/30.png>)

*Figure 5: Draft bucket policy built from IAM, plus the Lab 10 readiness file.*

- Bucket name read from Lab 1's policy, not typed.
- Allows the 5 roles only what they already have.
- Denies non-HTTPS requests and everyone else.
- Would block `usms-audit-01`.
- Draft only: nothing applied. `configs/lab-09.env` now has 17 exports.
- Bucket policy vs IAM policy: IAM stops one role; a bucket policy stops everyone, even other accounts.
