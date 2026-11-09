# LAB 6 

## 1. Objectives
Register the usms-enrolment service as a scalable target with a floor of 2 and a ceiling of 10 tasks.
Add target tracking policies (CPU and request count) and a step scaling policy with its own alarm.
Schedule bounds changes, suspend and resume scaling, and prove the configuration survives a restart.
Save the settings to configs/lab-06.env and check everything with verify-lab-06.sh.

## 2. Prerequisites
Labs 01 to 05 are complete: the VPC and subnets (Lab 02), the usms-enrolment-svc service running 2 tasks (Lab 04), and the load balancer and target group (Lab 05).
Floci is running under Docker Compose with persistent storage, with the AWS CLI and python3 installed.
The environment files from Labs 01 to 05 are loaded.

## 7. Step-by-Step Implementation
### Step 1 - Resume the environment and load six env files
Bring Floci up and load what Labs 01 to 05 recorded. Step 9 cannot build its composite string without the load balancer and target group ARNs.

![alt text](<../../screenshots/Lab 6 screenshots/1.png>)

*Figure 1: Floci is running and the six env files are loaded: cluster usms-ecs-cluster, service usms-enrolment-svc, baseline desired count 2.*

### Step 2 - Confirm Labs 02, 03, 04 and 05 are still intact
![alt text](<../../screenshots/Lab 6 screenshots/2.png>)
*Figure 2: The resources from Labs 02 to 05 still exist, so Lab 06 can build on them.*

### Step 3 - Probe what this Floci build supports

![alt text](<../../screenshots/Lab 6 screenshots/3.png>)
*Figure 3: The probe shows which Application Auto Scaling and CloudWatch calls this Floci build supports. Scheduled actions turned out to be the main gap.*

### Step 4 - Create the service-linked role that writes desiredCount

![alt text](<../../screenshots/Lab 6 screenshots/4.png>)
*Figure 4: The service-linked role AWSServiceRoleForEcsApplicationAutoscaling exists, trusts ecs.application-autoscaling.amazonaws.com and sits under the /aws-service-role/ path. No managed policy is attached on Floci.*

### Step 5 - Register the scalable target

![alt text](<../../screenshots/Lab 6 screenshots/5.png>)

*Figure 5: The scalable target service/usms-ecs-cluster/usms-enrolment-svc is registered with Min 2 and Max 10, and the service stays at Desired 2 with one deployment.*

### Step 6 - Change the bounds, and learn what a re-registration is

![alt text](<../../screenshots/Lab 6 screenshots/6.png>)

*Figure 6: Re-registering the same resource ID changed Max from 10 to 12 while the omitted Min stayed at 2. Re-registering with 2 and 10 restored the bounds, and only one scalable target exists.*

### Your Turn 

**Prediction:** Raising MinCapacity to 5 while 2 tasks are running should make Application Auto Scaling raise desiredCount to 5 within seconds, with no policy or alarm involved.

![alt text](<../../screenshots/Lab 6 screenshots/7.png>)

*Figure 6: After raising MinCapacity to 5, desiredCount stayed at 2 and no scaling activity was recorded. The floor was then restored to 2, with Desired 2 and one deployment.*

#### observation and limitation
Observation: desiredCount did not move and describe-scaling-activities returned an empty list. Floci accepted the new MinCapacity but did not enforce it against the running service. Real AWS would have raised desiredCount to 5 immediately. The restore was safe, since the count was already 2.

### Step 7 - Create the CPU target tracking policy

![alt text](<../../screenshots/Lab 6 screenshots/8.png>)

*Figure 7: The CPU target tracking policy usms-enrolment-cpu-target-tracking is attached to the scalable target, targeting 50% average CPU with a 60 s scale-out cooldown and a 300 s scale-in cooldown.*

### Step 8 - Read the two alarms that target tracking created for you

![alt text](<../../screenshots/Lab 6 screenshots/9.png>)

*Figure 8: The two alarms created by the CPU target tracking policy. AlarmHigh needs 3 evaluations to trigger scale-out, while AlarmLow needs 15 to trigger scale-in. Both are in INSUFFICIENT_DATA and each has one action.*

### Step 9 - Create the request-count policy, the row Lab 05 unlocked

![alt text](<../../screenshots/Lab 6 screenshots/10.png>)

*Figure 9: The ALB request-count policy’s ResourceLabel passes validation: six segments, app first and targetgroup fourth. Both target tracking policies are attached, CPU at 50.0 and requests at 1000.0, each with two managed alarms*

###  Step 10 - Create a step scaling policy, and the alarm that drives it
![alt text](<../../screenshots/Lab 6 screenshots/11.png>)

*Figure 10: The step scaling policy usms-enrolment-queue-step-out adds 1 task for a queue depth of 100 to 200 and 3 tasks above 200, with no upper bound on the top step. The alarm usms-enrolment-queue-high triggers it when EnrolmentQueueDepth reaches 100.*

### Step 11 - Create two scheduled actions

![alt text](<../../screenshots/Lab 6 screenshots/12.png>)

*Figure 11: Both put-scheduled-action and describe-scheduled-actions fail on Floci with UnsupportedOperation, so scheduled actions can’t be created or listed on this build.*

Limitation: Floci supports neither PutScheduledAction nor DescribeScheduledActions, so the two scheduled actions could not be created or listed. Real AWS would create usms-enrolment-morning-scale-out (cron(45 7 ? * MON-FRI *), Asia/Thimphu, Min 4 Max 10) and usms-enrolment-evening-scale-in (cron(0 20 ? * MON-FRI *), Asia/Thimphu, Min 2 Max 10).

### Step 12 - Fire the alarm, and prove that something other than you moved the number

![alt text](<../../screenshots/Lab 6 screenshots/13.png>)

*Figure 12: With the queue metric at 260, usms-enrolment-queue-high triggered usms-enrolment-queue-step-out, raising desiredCount 2 → 5 → 8 → 10 (the ceiling). After the metric was pushed down, the count was reset to 2, matching the pre-scale baseline.*

### Step 13 - Suspend and resume scaling

![alt text](<../../screenshots/Lab 6 screenshots/14.png>)

*Figure 13: Scale-in suspension through register-scalable-target --suspended-state, with only DynamicScalingInSuspended true and the bounds unchanged. After resuming, all three switches are false and grep -ci true returns 0.*

### Step 14 - Prove the whole scaling configuration survives a restart

![alt text](<../../screenshots/Lab 6 screenshots/15.png>)

*Figure 14: After restarting Floci, the resource ID, dimension, policy names and alarm were re-derived from the API, and the pre- and post-restart configuration files are identical, so the scalable target, both policies and the queue alarm survived the restart.*

### Step 15 - Close the loop: from one request to one new task
![alt text](<../../screenshots/Lab 6 screenshots/16.png>)

*Figure 15: The chain from metric to new task, read from live objects: three alarms and their policies, desiredCount bounded 2 to 10, two healthy targets in usms-enrolment-tg, and one deployment with one load balancer entry. The service is on usms-enrolment:3, created before Lab 06 (see notes).*

### Step 16 - Write configs/lab-06.env
![alt text](<../../screenshots/Lab 6 screenshots/18.png>)

*Figure 16: configs/lab-06.env has 22 exports, bounds 2 to 10, and a resource ID that matches what the API reports.*

### Verifications

![alt text](<../../screenshots/Lab 6 screenshots/19.png>)

*Figure 17: verify-lab-06.sh reports PASS=39 FAIL=3. The three failures are the scheduled-action checks, which cannot pass because Floci does not implement scheduled actions.*

### Analysis
I learned that auto scaling changes only one number, desiredCount, between a minimum and a maximum. Target tracking adjusts it automatically, step scaling needs an alarm I create, and scheduled actions prepare for busy times I already know about. On Floci everything works and survives a restart, but scheduled actions are not supported and the minimum is not enforced.


