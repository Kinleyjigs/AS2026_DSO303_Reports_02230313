# Lab 09: Exercises

### Exercise 1 - Egress for the web tier
![alt text](<../../screenshots/Lab 9 screenshots/26.png>)

*Figure 1: usms-app-sg now has 6 written egress rules and no default rule; verify-lab-09 is still PASS=50 FAIL=0.*

In this exercise I replaced the default "allow everything out" rule on `usms-app-sg` with rules for only what the web server actually needs. It needs to reach S3 for the transcripts (through the S3 prefix list), AWS services such as STS over HTTPS (port 443), the enrolment API through the load balancer (port 80 to `usms-alb-sg`), the database (port 5432 to `usms-db-sg`), and DNS (port 53 to `10.0.0.2`, the VPC's built-in DNS server).

DNS needs two rules, because it normally uses UDP but switches to TCP for large answers. The load balancer and the database are named by their security group instead of an IP address, because their IPs can change but the group stays the same. I added the new rules first and only then removed the default rule, so there was never a moment with no outbound access. The metadata address `169.254.169.254` does not need a rule, because security groups do not filter it. The bastion is different: its only job is to start SSH sessions, so its egress should only be port 22 to `usms-app-sg`.

### Exercise 2 - Break-glass role
![alt text](<../../screenshots/Lab 9 screenshots/27.png>)

*Figure 2: Break-glass role with MFA + ExternalId, 1-hour session and a boundary. IAM audit: HIGH=0, 4 ACCEPTED.*

I created `usms-breakglass-role`, an emergency role for suspending auto scaling. Only `usms-admin-01` can use it, and only if they have signed in with MFA **and** give the correct ExternalId. Because both conditions are in the same block, both must be true. The session lasts at most one hour (the shortest IAM allows), the role has the permissions boundary, and it can only call the two Application Auto Scaling actions that Lab 6 used to suspend scaling.

I also dealt with the roles that the audit flagged for having no conditions in their trust policy. I fixed the ECS execution role and the Lambda role by adding `aws:SourceAccount` and `aws:SourceArn`. The EC2 and EKS roles could not be fixed this way, because EC2 does not send those keys, so I accepted them with a reason (IMDSv2 and the PassRole deny protect them instead). The service-linked role was also accepted, because AWS controls its trust policy. These decisions are written in `configs/usms-iam-accepted-findings.tsv`, and the audit script now shows them as `ACCEPTED` instead of HIGH. The audit ended with HIGH=0.

### Exercise 3 - Exposure report
![alt text](<../../screenshots/Lab 9 screenshots/28.png>)

*Figure 3: Same output from two folders. 16 interfaces classified by route, public IP and SG.*

I wrote `usms-exposure-report.sh`, which looks at every network interface in the VPC and decides how exposed it is. It checks three things: whether the interface has a public IP, whether its subnet has a route to the internet gateway, and whether its security group allows traffic from the internet. It never looks at names or tags. The script gave the same output when run from my home folder and from the lab folder.

The result was that only `usms-web-01` is fully exposed to the internet. `usms-web-02` has an open security group but no public IP, so it cannot be reached. The ECS tasks and the database are private. The NAT gateway has a public IP but no rules allowing traffic in, so I marked it "public but closed": it is safe today, but only one rule change away from being exposed. Two old task interfaces were marked "unknown" because their security group no longer exists. I did not use `set -e`, so one failed command does not stop the whole report.

### Exercise 4 - Security review
![alt text](<../../screenshots/Lab 9 screenshots/29.png>)

*Figure 4: Who can read transcripts: 3 roles read/write, 2 roles read, and usms-audit-01 through its group.*

**The second front door.** The load balancer is meant to be the only public entry point, but `usms-web-01` is still open to the internet on ports 80 and 443 from Lab 3. I recommend putting it behind the load balancer and then closing those rules. This would break anyone who uses the server's IP directly, and the load balancer would need an HTTPS listener first.

**What egress control bought.** Restricting outbound traffic stops an attacker from sending data out through DNS, opening a reverse shell on an unusual port, or using our servers to attack others over SSH or email. It does not stop data being sent out over HTTPS (port 443 is still open), and it does not stop someone copying transcripts to their own S3 bucket. Those would need AWS Network Firewall and an S3 bucket or endpoint policy.

**Who can read the transcripts.** The EC2, ECS task and EKS node roles can read, write and delete transcripts. The transcripts reader role and the Lambda role can only read. I also found that `usms-audit-01` can read every transcript through the `usms-auditors` group, which nobody planned. On real AWS, IAM Access Analyzer would confirm this list is complete. Floci cannot do that, so I checked every policy and group by hand.

| Who | Access | Through |
|---|---|---|
| ec2-app, ecs-task, eks-node roles | Read, write, delete | USMSStudentDataReadWrite |
| transcripts-reader role | Read | USMSStudentDataReadOnly |
| lambda-exec role | Read | USMSLambdaBasic |
| usms-audit-01 | Read (unplanned) | usms-auditors group |

**Detection.** To know when something changes, I would turn on CloudTrail (free for management events), GuardDuty, AWS Config, IAM Access Analyzer and VPC Flow Logs. These only detect problems; the security groups and policies from this lab are what prevent them. After an incident I would read CloudTrail first, then GuardDuty findings, then the Flow Logs, then the S3 access logs.

**Moving the web server behind the load balancer (written, not run).** First create a target group and register `usms-web-01`. Then add a listener rule on the load balancer, allow port 80 into `usms-app-sg` from `usms-alb-sg`, and allow the load balancer's egress to reach `usms-app-sg`. Check that the target is healthy. Only then remove the 80/443 rules from `0.0.0.0/0`. This last step is the dangerous one: it can be undone by adding the rules back, but it breaks direct access and the Lab 3 verify check.

### Exercise 5 - Bucket policy draft
![alt text](<../../screenshots/Lab 9 screenshots/30.png>)

*Figure 5: Draft bucket policy built from IAM, plus the Lab 10 readiness file.*

The script `usms-bucket-policy-draft.sh` creates a draft bucket policy and a readiness report for Lab 10. It reads the bucket name from Lab 1's policy instead of typing it, and it finds the five roles that already have S3 access to the bucket. Each role is allowed only the actions it already has.

The policy also blocks any request that does not use HTTPS, and blocks every other user apart from those five roles and the account root. All the checks passed, and I added the draft's path to `configs/lab-09.env` (now 17 exports). The script only creates a draft and does not change anything in AWS. I also noticed this policy would block `usms-audit-01`, which fixes the unplanned access found in Exercise 4. The difference from an IAM policy is that an IAM policy only affects the role it is attached to, while a bucket policy controls access for everyone, including users from other AWS accounts.
