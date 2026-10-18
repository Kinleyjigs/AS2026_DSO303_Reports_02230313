# Lab 04 - Exercises

## Exercise 1 - A second service, deployed

|                   DescribeServices                   |
+---------+----------------------+----------+----------+
| Desired |        Name          | Running  | Status   |
+---------+----------------------+----------+----------+
|  2      |  usms-enrolment-svc  |  2       |  ACTIVE  |
|  1      |  usms-results-svc    |  1       |  ACTIVE  |
+---------+----------------------+----------+----------+

|   ListTagsForResource  |
+------------------------+
||         tags         ||
|+----------+-----------+|
||    key   |   value   ||
|+----------+-----------+|
||  Project |  USMS     ||
||  Tier    |  app      ||
||  Service |  results  ||
||  Lab     |  04       ||
|+----------+-----------+|

**Notes:** usms-results-svc reuses the usms-enrolment task definition family; only the service
name, desired count (1) and tags changed. Subnet and security group IDs were looked up by Name
tag with --query, not copied. Not recorded in configs/lab-04.env because Exercise 4 deletes it.

## Exercise 2 - A new revision, and a deployment that does not drop traffic

### Service now runs revision 2
------------------------------------------------------------------
|                        DescribeServices                        |
+---------+----------+----------------------+--------------------+
| Desired | Running  |       Service        |      TaskDef       |
+---------+----------+----------------------+--------------------+
|  2      |  2       |  usms-enrolment-svc  |  usms-enrolment:2  |
+---------+----------+----------------------+--------------------+
### Revision 1 still exists
----------------------------------
|     DescribeTaskDefinition     |
+--------+------------+----------+
| Memory | Revision   | Status   |
+--------+------------+----------+
|  512   |  1         |  ACTIVE  |
+--------+------------+----------+
### Revision 2
----------------------------------
|     DescribeTaskDefinition     |
+--------+------------+----------+
| Memory | Revision   | Status   |
+--------+------------+----------+
|  1024  |  2         |  ACTIVE  |
+--------+------------+----------+

**What changed:** the service's `taskDefinition` field changed from `usms-enrolment:1` to
`usms-enrolment:2`, while revision 1 itself did not change at all - revisions are immutable,
only the service's pointer to one moves.

Revision 1 stays ACTIVE because deregistering is a separate action this exercise did not take.
The original template (templates/lab-04-taskdef.json) was kept; revision 2 came from a copy
(templates/lab-04-taskdef-rev2.json).

## Exercise 3 - ECS configuration drift report

Script: scripts/utilities/lab-04-ecs-inventory.sh (JSON copy: outputs/lab-04-ecs-inventory.json)
```
usms-enrolment-svc     desired=2   running=2   taskdef=usms-enrolment:2     roles=SEPARATE  publicip=OK
usms-results-svc       desired=1   running=1   taskdef=usms-enrolment:2     roles=SEPARATE  publicip=OK
```
Output was identical when run from ~ and from labs/lab-04-ecs/.
No set -e: a report should print N/A/unknown for one failing service and continue, not abort.
Note: Floci stores the service taskDefinition as given (family only for usms-results-svc), so it resolves to the latest revision.

## Exercise 4 - Enrolment week capacity plan

### 1. Why a fixed desiredCount of 2 cannot answer the 08:03 problem
usms-enrolment-svc reads no metric and no clock. Its desiredCount changes only when a
human runs `aws ecs update-service --desired-count`. At 08:00 load jumps sharply, the two
tasks saturate, and nothing in the service reacts. Even if someone noticed and scaled by hand,
new Fargate tasks take 20-60 seconds to start, so capacity must be in place BEFORE 08:00,
not added after the failure. A fixed count also means we pay for the same 2 tasks at 3am on a
Sunday in July as on enrolment Monday.

### 2. Proposed plan (handed to Lab 06, not implemented here)
Assumptions (replace with measured USMS figures):
- 3,000 students register in enrolment week; 90% (2,700) in the first 20 minutes (1,200 s).
- ~10 HTTP requests per registration -> 27,000 requests / 1,200 s = 22.5 req/s average.
- Peak-to-average factor of 3 for the first minutes -> ~68 req/s peak.
- One 0.25 vCPU task handles ~10 req/s (must be confirmed by a load test in Lab 06).

| Setting | Value | Derivation | Too high costs... | Too low costs... |
|---|---|---|---|---|
| Minimum | 2 | one task per Availability Zone, survives an AZ loss | idle spend every night | single point of failure |
| Scheduled floor | 8, Mon 07:30-09:00 | 68 / 10 = 6.8 -> 7 tasks + 1 headroom = 8 (even, 4 per AZ) | ~$0.13 per enrolment morning wasted | repeat of the 08:03 outage |
| Maximum | 10 | scheduled floor + 2 for traffic above the estimate | runaway spend if a bug loops | throttled during a surprise spike |

Start the scheduled floor at 07:30, not 08:00, because Fargate start latency is 20-60 s and
tasks must be healthy before the first request. Outside the window, target tracking on
average CPU (aim ~60%) moves between the minimum 2 and maximum 10.
Note for Lab 06: this Floci build does not support describe-scheduled-actions
(UnsupportedOperation), so the scheduled floor will be documented, not executed.

### 3. Monthly cost comparison (current task size: 0.25 vCPU / 1 GB)
Source: AWS Fargate pricing, Linux/x86, US East (N. Virginia):
https://aws.amazon.com/fargate/pricing/ - $0.000011244 per vCPU-second, $0.000001235 per
GB-second = $0.04048 per vCPU-hour, $0.004445 per GB-hour.

Per task per hour = 0.25 x 0.04048 + 1 x 0.004445 = $0.014565. Month = 730 h.

| Option | Calculation | Per month |
|---|---|---|
| A. Fixed at today's 2 | 2 x 0.014565 x 730 | $21.26 |
| B. Fixed at peak 8 | 8 x 0.014565 x 730 | $85.06 |
| C. Proposed: 2 baseline + 6 extra for 1.5 h on enrolment Monday | $21.26 + (6 x 1.5 x 0.014565) | $21.39 |

Option C costs about $0.13 more than A in enrolment month and about $63.67 less than B,
while giving B's capacity during the only window that needs it.
(Check on the lab text: two 256/512 tasks cost 2 x (0.25x0.04048 + 0.5x0.004445) x 730 =
$18.02/month, slightly above the lab's "roughly USD 15".)

### 4. What to switch off: the Exercise 1 results service

> **DANGER - step 1: scale usms-results-svc to 0**
> What will be deleted: nothing yet; the service's 1 running task is stopped.
> What depends on it: nothing - it was Exercise 1 practice, not in configs/lab-04.env.
> Reversible? Yes, update-service --desired-count 1 restores it.
> Effect on later labs: none.

    aws ecs update-service --cluster usms-ecs-cluster --service usms-results-svc --desired-count 0
    aws ecs wait services-stable --cluster usms-ecs-cluster --services usms-results-svc

> **DANGER - step 2: delete usms-results-svc**
> What will be deleted: the usms-results-svc service only (the usms-enrolment task definition is shared and KEPT).
> What depends on it: nothing.
> Reversible? No - it would have to be recreated as in Exercise 1.
> Effect on later labs: none; usms-enrolment-svc, the cluster and all KEEP items are untouched.

    aws ecs delete-service --cluster usms-ecs-cluster --service usms-results-svc

## Exercise 5 - Close the loop back to Lab 3
```
Lab 04 -> Lab 03 linkage   (generated 2026-10-18T10:22:27Z)

usms-enrolment-sg ........ sg-3cbe6c82e300b3373
only inbound source ...... sg-8dca672a89099a5a5  (usms-app-sg)
resolves to instance ..... i-2be79ec06ed2b4cfb
configs/lab-03.env ....... i-2be79ec06ed2b4cfb  (usms-web-01)
verdict .................. LOOP CLOSED

Note: the first lookup returned no instance because usms-web-01 was stopped
(Floci restart). It was started with ec2 start-instances and the lookup re-run.
Other instances also carry usms-app-sg but are not running, so they are not callers:
i-51f94d437ecb27850	stopped
i-bd75bcc316ba408db	terminated
i-344ebab3eeb42d47a	stopped

This rule (tcp/80 from usms-app-sg) is temporary: Lab 05 removes it once the
Application Load Balancer becomes the only caller of the enrolment service.

== Tag audit (aws ecs list-tags-for-resource) ==
-- cluster: arn:aws:ecs:us-east-1:000000000000:cluster/usms-ecs-cluster
Project	USMS
Tier	app
Name	usms-ecs-cluster
-- service: arn:aws:ecs:us-east-1:000000000000:service/usms-ecs-cluster/usms-enrolment-svc
Project	USMS
Tier	app
Lab	04
Name	usms-enrolment-svc
Tag audit: all Project=USMS tags present on cluster and service; no fix needed.
```
Copy committed as labs/lab-04-ecs/lab03-linkage.txt because outputs/ is git-ignored.




## Independent Lab Exercises
### Exercise 1: A second service (usms-results-svc)

Objective:create a second service, the exam results service, in the same cluster using the same blueprint (usms-enrolment), but with 1 copy instead of 2. It runs in both private subnets, behind the same security group, and carries an extra tag Service=results.

#### 1. Start the exercises file

![alt text](<../../screenshots/Lab 4 screenshots/13.png>)

Exercise 1: usms-results-svc deployed from the same usms-enrolment task definition with desired count 1, alongside usms-enrolment-svc at 2.

### Exercise 2: A new revision, and a deployment that doesn’t drop traffic

![alt text](<../../screenshots/Lab 4 screenshots/14.png>)

usms-enrolment-svc rolled to revision 2 (1024 MiB), while revision 1 stays ACTIVE and describable.

### Exercise 3: ECS configuration drift report

![alt text](<../../screenshots/Lab 4 screenshots/15.png>)

Exercise 3: inventory script classifies every service in usms-ecs-cluster as roles=SEPARATE, publicip=OK, with identical output from two directories.

### Exercise 4: Enrolment-week capacity plan
![alt text](<../../screenshots/Lab 4 screenshots/16.png>)

practice service usms-results-svc deleted; only usms-enrolment-svc remains and verify-lab-04.sh still reports FAIL=0

### Exercise 5: Close the loop back to Lab 3

![alt text](<../../screenshots/Lab 4 screenshots/17.png>)

sms-enrolment-sg’s source group resolves back to usms-web-01 (LOOP CLOSED), and the ECS cluster and service carry Project=USMS tags.








