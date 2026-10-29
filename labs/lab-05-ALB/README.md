# Lab 05 ALB
---

## 1. Aim / Objective

Put Lab 04's `usms-enrolment-svc` behind an internet-facing Application Load Balancer so the private ECS tasks get one stable name, then cut over so the load balancer is the **only** thing that can reach the tasks.

## 2. Introduction

ECS tasks have private, temporary IP addresses that change every time a task is replaced. An Application Load Balancer (ALB) gives them a fixed DNS name. The ALB listens on HTTP:80, forwards to a **target group**, and the **ECS service** keeps that target group filled with the current task IPs. Health checks decide which targets get traffic.

## 3. Use Case

The USMS web tier (`usms-web-01`) used to call enrolment tasks by IP. With the ALB it calls one DNS name instead. Tasks can scale, restart or redeploy without the caller noticing, and only the ALB is allowed to reach them.

## 5. Implementation Procedure 
### Step 1: Resume the environment and load the env files
![alt text](<../../screenshots/Lab 5 screenshots/1.png>)

*Figure: whoami.sh output plus the twelve printed values.*

### Step 2: Confirm Labs 2, 3 and 04 are intact
![alt text](<../../screenshots/Lab 5 screenshots/2.png>)

*Figure: Pre-lab verification of Labs 02, 03 and 04. One existing failure was recorded and left unchanged.*

### Step 3: Probe ELBv2 support in Floci
![alt text](<../../screenshots/Lab 5 screenshots/3.png>)

*Figure: The probe shows which ELBv2 calls this Floci build supports.*

### Step 4: Create the load balancer's security group
![alt text](<../../screenshots/Lab 5 screenshots/4.png>)

*Figure: `usms-alb-sg` has one inbound rule, tcp/80 from 0.0.0.0/0.*

### Step 5: Create the Application Load Balancer
![alt text](<../../screenshots/Lab 5 screenshots/5.png>)

*Figure: describe-load-balancers JSON showing the ARN, DNS name, 2 AZs, scheme and state.*

### Step 6 and Step 7: Create the target group and set its attributes
![alt text](<../../screenshots/Lab 5 screenshots/6.png>)

*Figure: Target group JSON and its attributes table (deregistration delay 30s).*

### Step 8: Create the listener
![alt text](<../../screenshots/Lab 5 screenshots/7.png>)

*Figure: Listener on port 80 HTTP forwarding to `usms-enrolment-tg`, attached to 1 load balancer.*

### Step 9: Let the load balancer reach the tasks
![alt text](<../../screenshots/Lab 5 screenshots/8.png>)

*Figure: `usms-enrolment-sg` now admits tcp/80 from both `usms-app-sg` and `usms-alb-sg`.*

### Step 10: Attach the existing service to the target group


![alt text](<../../screenshots/Lab 5 screenshots/9.png>)

*Figure: The service is attached to usms-enrolment-tg (enrolment-api:80) with the task definition unchanged. The grace period shows null because Floci does not store it..*

### Step 11: Watch the targets register (Checkpoint 4)
![alt text](<../../screenshots/Lab 5 screenshots/10.png>)

*Figure : The ECS service registered its tasks in usms-enrolment-tg automatically, and two targets are healthy. Floci uses Docker addresses (172.20.0.x) instead of VPC subnet IPs, and 172.20.0.5 is a stale target from the recreated service.*

### Step 12: Prove the path

![alt text](<../../screenshots/Lab 5 screenshots/11.png>)

![alt text](<../../screenshots/Lab 5 screenshots/12.png>)

*Figure: The ALB DNS name does not resolve on Floci, so no data path was available. The control-plane proof shows the full chain: listener → target group → service-registered targets → enrolment SG admitting usms-alb-sg. Targets use Floci’s Docker addresses (172.20.0.x), not VPC subnet IPs.*

### Step 13: The cutover (remove the direct path)
![alt text](<../../screenshots/Lab 5 screenshots/13.png>)

*Figure: Cutover complete. The usms-app-sg rule was removed, and usms-enrolment-sg now admits port 80 only from usms-alb-sg. The Lab 04 result is unchanged (PASS=37 FAIL=1) because its one failure existed before this lab.*

### Step 14: Forced deployment and draining (Checkpoint 5)
![alt text](<../../screenshots/Lab 5 screenshots/14.png>)

*Figure: A forced deployment was accepted and marked COMPLETED, but Floci did not replace the tasks: the task ARNs and target list are unchanged. Draining could not be observed*

### Step 15: Add a listener rule

![alt text](<../../screenshots/Lab 5 screenshots/15.png>)
*Figure: Listener rules in evaluation order. Priority 10 matches /alb-health and returns a fixed 200; the default action forwards to usms-enrolment-tg. curl returned 000 because the ALB DNS name does not resolve on Floci*

### Step 16: Prove persistence across a restart (Checkpoint 7)

![alt text](<../../screenshots/Lab 5 screenshots/16.png>)
*Figure: After stopping and starting Floci, every ARN was re-derived from the API and the configuration diff was empty: PERSISTENCE PROVEN.*

### Step 17: Close the loop and audit

![alt text](<../../screenshots/Lab 5 screenshots/17.png>)
*Figure: Security audit. The ALB admits HTTP from the internet, and the enrolment tasks admit only usms-alb-sg (CUTOVER CONFIRMED). All Lab 05 resources are tagged Lab=05. The usms-web-01 lookup returned None because of a Floci limitation, so LOOP CLOSED could not be printed.*

## 6. Results and Evidence

| Item | Result |
|---|---|
| ALB `usms-enrolment-alb` | active, internet-facing, 2 AZs |
| Target group | 2 healthy targets, registered by the service |
| Listener + rule | HTTP:80 forward, rule 10 fixed-response 200 |
| Cutover | tasks accept tcp/80 from `usms-alb-sg` only |
| Persistence | PERSISTENCE PROVEN after restart |
| Config | `configs/lab-05.env` written for Lab 06 |

## 7. Verification
![alt text](<../../screenshots/Lab 5 screenshots/18.png>)

*Figure 14: verify-lab-05.sh reports PASS=47 FAIL=2. Both failures come from Floci not storing the 60-second grace period (None); this is a known benign failure. All other checks pass.*

Both failures are listed in the lab as **known benign** (`healthCheckGracePeriodSeconds is set`). `verify-lab-04.sh` now shows exactly one expected failure (`sourced from usms-app-sg`), because the architecture changed on purpose in Step 13.

## 8. Analysis and Discussion 

I learned how the ALB distributes traffic to ECS tasks and how the service automatically manages targets when scaling. I also learned to update the load balancer safely without downtime and use security groups to control access. During the lab, I also understood some Floci limitations and how to troubleshoot them.

## Conclusion

The enrolment service now sits behind an internet-facing ALB with a target group, a listener and one rule. The ECS service registers its own tasks, only the load balancer can reach them, and the setup survives a restart. The ARNs are saved in `configs/lab-05.env` for Lab 06 auto scaling. 




