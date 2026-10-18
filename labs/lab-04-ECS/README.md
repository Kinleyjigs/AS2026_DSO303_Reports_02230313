# Lab 04 - Amazon ECS
---

## 1. Aim / Objective

Containerise the USMS enrolment service onto Amazon ECS on Fargate, inside Lab 2's private subnets, and hand Labs 05 and 06 a service that stands still at `desiredCount` 2.

Specifically, this lab set out to:

- build an ECS cluster, a CloudWatch Logs log group, a task definition and a service holding a fixed `desiredCount` of 2 across two Availability Zones;
- separate the task **execution** role (pulls the image, writes logs) from the task **role** (the application's identity), and reuse Lab 1's `USMSStudentDataReadWrite` policy on the task role, unchanged;
- source the service's security group from the web tier's `usms-app-sg` rather than a CIDR block, and explain how a private-subnet task pulls its image;
- record every name and ARN in `configs/lab-04.env` for Labs 05 and 06.

## 2. Introduction

Lab 3 ran USMS on a single, hand-managed EC2 instance. If that instance failed, someone had to notice and log in to fix it. Amazon ECS replaces that model with four objects:

| Object | What it is | In this lab |
|---|---|---|
| **Cluster** | A namespace, not a machine | `usms-ecs-cluster` |
| **Task definition** | An immutable, versioned blueprint (image, CPU/memory, roles, logging) | `usms-enrolment:1`, later `:2` |
| **Task** | One running copy of a task definition | 2 tasks, one per private subnet |
| **Service** | A controller that keeps `runningCount` equal to `desiredCount` | `usms-enrolment-svc` |

**Fargate** removes the EC2 instances underneath the tasks, but not the network. With `awsvpc` networking, each task gets its own network interface in our subnet, with our security group, obeying our route tables. Auto scaling (Lab 06) only ever changes `desiredCount`; the service does the rest.

## 3. Use Case

The enrolment service is the endpoint the USMS student portal calls when a student clicks "Register for this module". It has to:

- survive the loss of one task or one Availability Zone without anyone logging in, so it runs two tasks in two AZs;
- be reachable **only** from the web tier, never from the internet, so it sits in private subnets with no public IP and a security group sourced from `usms-app-sg`;
- read and write student transcripts in S3 without a key on disk, through a task role;
- be ready for a load balancer (Lab 05) and auto scaling (Lab 06) without being rebuilt.

## 4. System Architecture / Design

![alt text](<../../screenshots/Lab 4 screenshots/architecture.png>)

**Key design decisions**

| Decision | Reason |
|---|---|
| Two separate roles | The execution role is used by ECS **before** the container starts; the task role is used by the code **inside** it. Separating them keeps each least-privilege. |
| Execution policy scoped to one log group | AWS's managed `AmazonECSTaskExecutionRolePolicy` allows writing to any log group; ours allows only `/usms/ecs/enrolment:*`. |
| Reuse `USMSStudentDataReadWrite` unchanged | One policy, two delivery mechanisms (instance profile in Lab 3, task role here). |
| Security group sourced from a group | Tasks have no stable IPs, and a CIDR would admit anything in the subnet. |
| `assignPublicIp=DISABLED`, private subnets | The enrolment API has no reason to be internet-reachable. |
| 256 CPU / 512 MiB | The smallest valid Fargate pair (raised to 1024 MiB in Exercise 2). |
| 7-day log retention | Without it, a log group keeps (and bills for) data forever. |


## 5. Implementation Procedure 
All commands were run from the repository root `~/aws-floci-course/`. After starting Floci and loading the env files from Labs 1 to 3, I confirmed that Labs 2 and 3 were still intact (FAIL=0 on both verify scripts) and probed which AWS services this Floci build supports. I then created the ECS cluster while temporarily holding usms-developer-role, created the /usms/ecs/enrolment log group with 7-day retention, and built the two IAM roles. The execution role got a least-privilege policy for image pulls and log writes, and the task role got Lab 1's USMSStudentDataReadWrite, reused unchanged. Next, I created usms-enrolment-sg, allowing tcp/80 only from the web tier's usms-app-sg, and wrote and registered the Fargate task definition usms-enrolment:1 (awsvpc, 256 CPU / 512 MiB, both roles, awslogs). With those pieces in place, I created usms-enrolment-svc with a desired count of 2 across both private subnets with no public IP, read it back, and scaled it by hand from 2 to 3 and back to 2. Finally, I recorded every name and ARN in configs/lab-04.env by API lookup, built the verification script (PASS=38 FAIL=0) and the end-of-course cleanup script (syntax-checked, not run), and committed the work using explicit paths.

## 6. Results and Evidence

### Step 1 - Resume the environment and load three env files

All eight values from earlier labs were non-empty (private subnets `subnet-9ec1885a` and `subnet-21ffdf71`, `usms-app-sg` `sg-8dca672a89099a5a5`, web instance `i-2be79ec06ed2b4cfb`, region us-east-1, account 000000000000). `$USMS_PRIVATE_RT` and `$USMS_POLICY_S3_RW` were also confirmed set, because later steps depend on them.

### Step 2 - Confirm Labs 2 and 3 are still intact

`verify-lab-02.sh` and `verify-lab-03.sh` both reported `FAIL=0`, so the private route table has no IGW route and `usms-web-01` carries `usms-app-sg`.

### Step 3 - Probe what this Floci build actually supports

![Floci probe](<../../screenshots/Lab 4 screenshots/1.png>)

*Floci capability probe: ECS, Application Auto Scaling, CloudWatch and CloudWatch Logs answer; two probes reported "not available".*

Both "not available" results were re-checked directly:

| Probe | Direct result | Interpretation |
|---|---|---|
| `ecs describe-services` | `ClusterNotFoundException: Cluster not found: probe` (exit 254) | **False negative.** ECS answered; the probe function treats any non-zero exit as unsupported. |
| `describe-scheduled-actions` | `UnsupportedOperation` (exit 254) | **Real gap.** Scheduled scaling is not implemented in this build. It doesn't affect Lab 04; recorded for Lab 06. |

**Support path recorded: A**, except scheduled actions.

### Step 4 - Create the ECS cluster, as the developer role

![Assume role and create cluster](<../../screenshots/Lab 4 screenshots/2.png>)

*Part 1 and 2: caller identity shows `assumed-role/usms-developer-role/lab04-ecs-build`, and `usms-ecs-cluster` is created with Container Insights requested.*

![Restore identity and verify cluster](<../../screenshots/Lab 4 screenshots/3.png>)

*Part 3 and verify: identity restored after `unset`; `usms-ecs-cluster` is ACTIVE with 0 services and 0 tasks.*

### Step 5 - Create the log group the tasks will write to

![Log group](<../../screenshots/Lab 4 screenshots/4.png>)

*`/usms/ecs/enrolment` created with 7-day retention and 0 stored bytes.*

### Step 6 - Create the task execution role

![Execution role](<../../screenshots/Lab 4 screenshots/5.png>)

*`usms-ecs-exec-role` trusts `ecs-tasks.amazonaws.com` and carries the least-privilege `USMSECSTaskExecution` policy (ECR pull plus log writes to one group only).*

### Step 7 - Create the task role, and reuse Lab 1's policy on it (Checkpoint 2)

![Task role](<../../screenshots/Lab 4 screenshots/6.png>)

*Checkpoint 2: `usms-ecs-task-role` carries Lab 1's `USMSStudentDataReadWrite`, unchanged and reused rather than copied.*

**Issue found and fixed:** the lab builds the policy ARN as `arn:aws:iam::${ACCOUNT_ID}:policy/${USMS_POLICY_S3_RW}`, but in my `configs/lab-01.env`, `USMS_POLICY_S3_RW` already holds the **full ARN**. The result was a doubled ARN and `NoSuchEntity`. The role itself had been created correctly, so I attached the policy using `--policy-arn "$USMS_POLICY_S3_RW"` directly and re-ran the policy read.

The policy allows `s3:GetObject`, `s3:PutObject` and `s3:ListBucket` on `usms-student-data` and denies `s3:DeleteBucket`. The same document now reaches two kinds of compute:

```
Lab 03  usms-web-01 -- instance profile -- usms-ec2-app-role  --+
                                                                +-- USMSStudentDataReadWrite
Lab 04  task        -- taskRoleArn      -- usms-ecs-task-role --+
```

### Step 8 - Create the enrolment security group, sourced from the web tier's group

![Security group](<../../screenshots/Lab 4 screenshots/7.png>)

*`usms-enrolment-sg` has one inbound rule, tcp/80 from `usms-app-sg` (FromCIDR null), plus the default allow-all egress the image pull relies on.*

### Step 9 - Write and register the task definition (Checkpoint 3)

![Task definition](<../../screenshots/Lab 4 screenshots/8.png>)

*Checkpoint 3: `usms-enrolment:1` is ACTIVE, `awsvpc`, FARGATE, 256 CPU / 512 MiB, with **different** execution and task role ARNs and logs going to `/usms/ecs/enrolment`.*

`grep -c '\$' templates/lab-04-taskdef.json` returned `0`, confirming the unquoted heredoc expanded every variable.

### Step 10 - Create the service in Lab 2's private subnets

![Service created](<../../screenshots/Lab 4 screenshots/9.png>)

*`usms-enrolment-svc` created (ARN `service/usms-ecs-cluster/usms-enrolment-svc`, the form Lab 06's scalable target needs); polling showed `desired=2 running=2 pending=0`.*

**Observation:** running `create-service` a second time returned `InvalidParameterException: Creation of service was not idempotent`. The service already existed, so nothing broke, but the failed run emptied `$SERVICE_ARN`, which I restored with a `describe-services` lookup.

### Step 11 - Read the service back, and learn the four numbers (Checkpoint 4)

![Service read back](<../../screenshots/Lab 4 screenshots/10.png>)

*Checkpoint 4: service ACTIVE on FARGATE, desired 2 / running 2 / pending 0, both private subnets, `usms-enrolment-sg`, `assignPublicIp` DISABLED; `list-tasks` returns 2.*

| Field | Value | Meaning |
|---|---|---|
| `desiredCount` | 2 | What I asked for; the only field auto scaling will write |
| `runningCount` | 2 | Tasks actually up |
| `pendingCount` | 0 | Nothing stuck starting |
| `status` | ACTIVE | Not draining or deleted |

**Your turn - manual scaling 2 → 3 → 2**

![Your turn](<../../screenshots/Lab 4 screenshots/11.png>)

*`desiredCount` changed by hand with `aws ecs update-service` from 2 to 3 and back to 2; the service reconciled `runningCount` each time.*

This is exactly what an Application Auto Scaling policy will do in Lab 06: change `desiredCount` and let the service reconcile. In this build the service `events` list is empty (`None`), so the counts themselves are the evidence.

### Step 12 - Write `configs/lab-04.env`

![lab-04.env](<../../screenshots/Lab 4 screenshots/12.png>)

*`configs/lab-04.env` written by lookup: all values populated, 17 exports, baseline desired = 2.*



## 7. Verification
The custom script `verify-lab-04.sh` checked the environment, the dependencies from earlier labs, both IAM roles, the log group, the cluster, the task definition, the service, the security group and Git hygiene. It reported 38 PASS and 0 FAIL, and it still passed after the Exercise 4 practice service was deleted. The end-of-course cleanup script lab-04-cleanup.sh was syntax-checked with bash -n but deliberately not run, because Labs 05 and 06 depend on these resources.

![alt text](<../../screenshots/Lab 4 screenshots/18.png>)

## 8. Analysis and Discussion 
This lab moved the USMS enrolment service from a single hand-managed EC2 instance to a self-healing ECS service that keeps two tasks running across two Availability Zones. Splitting the execution role from the task role kept each identity least-privilege: ECS uses one to pull the image and write logs, while the application uses the other to reach S3. The same Lab 1 policy now reaches both EC2 and Fargate without any key on disk. Sourcing the security group from usms-app-sg instead of a CIDR block ties access to the web tier itself rather than to IP addresses, which matters because tasks have no fixed IPs. Because the tasks sit in private subnets with no public IP, they depend on Lab 2’s NAT gateway to pull their image. Scaling the service by hand from 2 to 3 and back showed that a fixed desiredCount cannot react to load on its own, which is the gap Lab 06 will fill. Several Floci limitations were recorded, including an empty events list, unsupported scheduled actions and a stopped web instance after a restart.

##  Conclusion

All Lab 04 objectives were met, and verify-lab-04.sh reported 38 PASS and 0 FAIL. The enrolment service now runs on ECS Fargate as a private, least-privilege and highly available container tier, and every name and ARN is saved in configs/lab-04.env, ready for the load balancer in Lab 05 and auto scaling in Lab 06.
