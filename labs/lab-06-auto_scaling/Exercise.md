### Exercise 1

![alt text](<../../screenshots/Lab 6 screenshots/20.png>)

*Figure 1: The memory target tracking policy targets 70% memory, with 60 s scale-out and 600 s scale-in cooldowns and DisableScaleIn true. The target’s managed alarm count rose from 4 to 5.*

#### Q. Why five and not six? Which alarm was not created, and what does its absence mean?
AlarmLow should not have been created, because it only triggers scale-in and DisableScaleIn is true, so on real AWS the count is 5 and the policy can add tasks but never remove them. Floci stored the flag but created AlarmLow anyway, giving 6.

#### Q. Memory target 70 against CPU target 50: which scales out first, and what would you need to know to answer properly?
it depends on which metric hits its own target first. To know, I’d need the service’s real CPU and memory usage under load.

#### Q. Does a scale-out-only policy change the scale-in behaviour of the other two? Use Step 9's rule.
No. Scale-in needs every policy that can scale in to agree, and a policy with scale-in disabled takes no part. It can only add scale-out requests, and the largest one wins.

### Exercise 2 
![alt text](<../../screenshots/Lab 6 screenshots/21.png>)

*Figure 2: With the queue metric at 5 and usms-enrolment-queue-low forced into ALARM, desiredCount stayed at 2 and no new scaling activity was recorded. The two activities shown are the earlier Step 12 scale-out events, not a scale-in. The floor of 2 leaves nothing to remove.*

### Exercise 3 
![alt text](<../../screenshots/Lab 6 screenshots/22.png>)

*Figure 3: usms-scaling-report.sh discovers the usms- scalable target and prints its bounds, suspension state, three scaling policies with their alarms, scheduled actions and last activity, ending in a computed verdict. Scheduled actions show as unavailable because Floci does not implement them.*

### Exercise 5 
![alt text](<../../screenshots/Lab 6 screenshots/23.png>)

*Figure 4: usms-scaling-history.sh exports the target, four policies, their alarms and the scaling activities to outputs/lab-06-scaling-history.json with a UTC generated stamp and a resourceId taken from the service ARN. The file is valid JSON of the size shown. Scheduled actions are null because Floci does not implement them.*

![alt text](<../../screenshots/Lab 6 screenshots/24.png>)
*Figure 5: Scale-out latency test: the floor was raised to 4 and the service polled for 101 seconds, but desired and running stayed at 2 because Floci does not enforce the floor. The latency is therefore cited from AWS’s Fargate start-up figure, not measured. The floor was restored to 2 and verification still shows only the three scheduled-action failures.*

![alt text](<../../screenshots/Lab 6 screenshots/25.png>)
*Figure 6: The Lab 10 readiness file: the history export’s path and size, the cited 120 s scale-out latency, the task role ARN, the bucket ARN read from the policy document, and the failing head-bucket call with its exit code, which should become 0 after Lab 10’s first step.*

### Exercise 4

**Is it solved?** Reactive scaling follows steady load well and keeps cost proportional to demand. It is bad at spikes, because a metric must be breached before a task even starts. It does not solve the first twenty minutes of each cohort day, since extra tasks take 5 to 7 minutes to serve traffic and the ceiling of 10 cannot carry 40x traffic.

**Why 40x is not only a scaling problem**
- Target tracking, 2 to 10 tasks: alarm 3 x 60 = 180 s, then one action per 60 s cooldown (180, 240, 300 s), then 60 s start-up + 60 s grace for the last task: 300 + 120 = 420 s (7 min).
- Step policy (+3 each time, 1 x 60 s alarm): actions at 60, 120 and 180 s give 2, 5, 8 then 10 tasks; last task serving at 180 + 60 + 60 = 300 s (5 min).
- Ceiling 10 x 1000 requests per target per minute = 10,000 per minute = about 167 requests per second (16.7 per task). That is capacity, not proven throughput.
- 40x normal traffic needs about 80 tasks at the target, eight times the ceiling.

**Ceiling vs Lab 02 subnets.** Each /24 has 256 addresses minus 5 reserved by AWS = 251 usable (AWS VPC User Guide, "Subnet CIDR blocks"). Free now: subnet A 246, subnet B 251, total 497. Deployments can briefly double the task count, so a safe ceiling is about 248. Fargate vCPU quotas were not checked.

**Capacity plan (Asia/Thimphu).** Assumed: opens 14 Nov 2026, cohort days 14, 21 and 28 Nov, 08:00 start.

| Action | Schedule | Min | Max |
|---|---|---|---|
| window-open | at(2026-11-14T00:00:00) | 4 | 20 |
| cohort pre-scale | cron(30 7 14,21,28 11 ? 2026) | 40 | 80 |
| cohort release | cron(30 9 14,21,28 11 ? 2026) | 4 | 20 |
| window-close | at(2026-12-05T00:00:00) | 2 | 10 |

Each is reversible in one command (`delete-scheduled-action`, `register-scalable-target` or `put-scaling-policy`). Floci cannot create scheduled actions, so this plan is untested.

**Cost (us-east-1).** Task 0.25 vCPU + 0.5 GB: 0.25 x $0.04048 + 0.5 x $0.004445 = $0.0123425 per hour (AWS Fargate pricing). Extra task-hours over the baseline of 2: 2 x 498 + 38 x 6 = 1,224. Fargate cost: 1,224 x $0.0123425 = $15.11. CloudWatch: 5 alarms x $0.10 + 1 custom metric x $0.30 = $0.80 a month (free tier may cover it). Total about $15.9; the load balancer, data transfer and logs are not estimated.

**What I need from the project lead**
1. A load test: requests per second one task can serve (nobody has measured it).
2. The exact cohort dates, start times and the normal request rate.
3. Approval of about $16 and a Fargate vCPU quota check (80 tasks = 20 vCPU).

**Tidy-up.** Deleted `usms-enrolment-memory-target-tracking` with its danger note, then ran verify-lab-06.sh: only the 3 scheduled-action checks fail (Floci limitation).


