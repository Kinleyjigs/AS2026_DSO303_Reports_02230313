
# Lab 1 : Identity and Access Management (IAM)

## 1. Aim / Objective
The objective of this practical is to learn how AWS Identity and Access Management (IAM) is used to securely manage users, groups, roles, and permissions within an AWS account. This lab used the AWS CLI v2 together with Floci, a local AWS emulator, to build a complete IAM foundation for a fictional university system (USMS) without incurring any real AWS cost.

## 2. Introduction
AWS Identity and Access Management (IAM) is a global AWS service that enables administrators to securely manage authentication and authorization for AWS resources. IAM allows organizations to create users, organize them into groups, assign permissions through policies, and grant temporary access using roles.
IAM does not incur additional charges and is considered one of the foundational services in AWS security. This lab also introduced Floci, a local, Docker-based emulator that exposes an AWS-compatible API on localhost:4566, allowing every IAM command to be practiced safely and repeatably before ever touching a real AWS account.

### Key Features Covered
- User Management
- User Groups
- IAM Roles and Trust Policies
- IAM Policies (AWS managed, customer managed, inline)
- Fine-grained Access Control (least privilege)
- Temporary Security Credentials via AWS STS
- Policy Simulation

## 3. Use Case
A university deploying a Unified Student Management System (USMS) needs to give developers, auditors, and administrators different levels of AWS access. Instead of granting every team member full administrator access, the cloud administrator creates IAM groups so that permissions are assigned once, at the group level, and inherited by every member. This enforces the Principle of Least Privilege and keeps access easy to audit.

| IAM Group | Permissions Granted |
|---|---|
| usms-admins | USMSDeveloperBase (build/read access) plus assume-role rights |
| usms-developers | USMSDeveloperBase (read infrastructure + build VPC networking); inline self-service credential policy on individual users |
| usms-auditors | ReadOnlyAccess (AWS managed policy) |


## 5. Implementation Procedure
The practical began by configuring the AWS CLI (via Floci) and verifying connectivity with aws sts get-caller-identity. Three IAM groups (admins, developers, auditors) were created, and three users were added to their matching groups.

Permissions were granted mainly at the group level: ReadOnlyAccess (AWS managed) for auditors, and two custom policies (USMSDeveloperBase, USMSStudentDataReadWrite) for developers and admins. An inline policy was also attached to one user to contrast it with managed policies. Two service roles (EC2, Lambda) were created with trust policies, plus a third role assumable by developers via aws sts assume-role. A permanent access key was also generated for one user, stored with restricted permissions and confirmed to be Git-ignored.

Configuration was verified throughout with CLI list/get commands, with outputs and screenshots captured as evidence (see Section 6).

## 6. Results and Evidence
### PART A — Environment Setup


#### Start Floci: Ran ./scripts/setup/floci-up.sh to bring the environment up with a verified host bind mount.
![alt text](<../../screenshots/Lab 1 screenshots/1.png>)

####  (Health check): Verified Floci was reachable via docker compose ps, floci status, and curl http://localhost:4566/_floci/health.
![alt text](<../../screenshots/Lab 1 screenshots/2.png>)

#### This will verify which column tells us where each value came from, and explain why the Type for the access key says shared-credentials-file.
![alt text](<../../screenshots/Lab 1 screenshots/3.png>)

#### Create the floci AWS CLI profile
![alt text](<../../screenshots/Lab 1 screenshots/4.png>)

#### Your first AWS CLI command, and the whoami helper
![alt text](<../../screenshots/Lab 1 screenshots/5.png>)

#### Prove isolation from real AWS, and prove persistence 
inspect the actual URL the CLI used
![alt text](<../../screenshots/Lab 1 screenshots/6.png>)


#### first AWS CLI command, and the whoami helper
here we ask the emulator "who am I?" the single most useful diagnostic command in AWS and wrap it in a script that will run at the start of every lab.
![alt text](<../../screenshots/Lab 1 screenshots/7.png>)

#### Prove isolation from real AWS, and prove persistence
inspect the actual URL the CLI used
![alt text](<../../screenshots/Lab 1 screenshots/8.png>)


stop the container
![alt text](<../../screenshots/Lab 1 screenshots/9.png>)

Persistence — the test that actually matters
![alt text](<../../screenshots/Lab 1 screenshots/10.png>)

Clean up the marker & Exit codes
![alt text](<../../screenshots/Lab 1 screenshots/11.png>)

**Floci Limitation: identity is not really authenticated**
    
    Real AWS verifies your signature cryptographically and rejects wrong credentials. Floci accepts any non-empty credentials by default, and reports you as the account root user. So get-caller-identity in Floci confirms connectivity, not authentication.

#### Storage diagnostics, README, and commit Part A
![alt text](<../../screenshots/Lab 1 screenshots/12.png>)

# PART B — Building the IAM Foundation (Steps 16–33)

#### IAM concepts and the anatomy of an ARN
#### Purpose
Understand the vocabulary before typing commands. Five minutes here saves an hour of confusion later.

#### Floci Limitation: policies are stored, not enforced (by default)
    Real AWS evaluates every request against IAM policies and returns AccessDenied when they do not permit it. Floci, by default, accepts any non-empty credentials and does not authorize requests against your IAM policies unless stricter authentication is explicitly enabled.


#### Inspect the empty IAM account

![alt text](<../../screenshots/Lab 1 screenshots/17.png>)

#### Create the IAM groups
![alt text](<../../screenshots/Lab 1 screenshots/18a.png>)

create-group creates an empty IAM group. A group has no permissions and no members at birth, it is purely a container. Note there is no --region: IAM is global.

verify
![alt text](<../../screenshots/Lab 1 screenshots/18b.png>)

#### Create the IAM users and capture their ARNs
Creating three users, and learning the single most important AWS CLI habit.

![alt text](<../../screenshots/Lab 1 screenshots/19a.png>)

Verify
![alt text](<../../screenshots/Lab 1 screenshots/19b.png>)

#### Add users to groups
![alt text](<../../screenshots/Lab 1 screenshots/20.png>)

#### Explore and attach an AWS managed policy
Explore what is available
![alt text](<../../screenshots/Lab 1 screenshots/21.png>)

#### Write your first customer managed policy
![alt text](<../../screenshots/Lab 1 screenshots/22a.png>)

![alt text](<../../screenshots/Lab 1 screenshots/22b.png>)

#### Write the S3 data policy (used for real in Lab 4)
Writing the policy that will govern student transcript storage, and get the bucket-vs-object ARN distinction right.

![alt text](<../../screenshots/Lab 1 screenshots/23.png>)

![alt text](<../../screenshots/Lab 1 screenshots/23b.png>)

#### Use --generate-cli-skeleton to discover parameters
![alt text](<../../screenshots/Lab 1 screenshots/24.png>)

#### Add an inline policy (self-service credentials)

![alt text](<../../screenshots/Lab 1 screenshots/25.png>)

#### Inspect what you have built
Everything about one user
![alt text](<../../screenshots/Lab 1 screenshots/26a.png>)

Read the actual policy JSON back out
![alt text](<../../screenshots/Lab 1 screenshots/26b.png>)

#### Policy versions
![alt text](<../../screenshots/Lab 1 screenshots/27.png>)

#### Create a role for EC2, with a trust policy
![alt text](<../../screenshots/Lab 1 screenshots/28a.png>)

give permission 
![alt text](<../../screenshots/Lab 1 screenshots/28b.png>)

Create the instance profile & verify 
![alt text](<../../screenshots/Lab 1 screenshots/28c.png>)

#### Create the Lambda execution role
create lumbda function and verify 
![alt text](<../../screenshots/Lab 1 screenshots/29.png>)

#### A role for humans, and temporary credentials with STS
Create the role with an account-principal trust policy

![alt text](<../../screenshots/Lab 1 screenshots/30a.png>)

Give the developers group permission to assume it
![alt text](<../../screenshots/Lab 1 screenshots/30b.png>)

Assume the role
![alt text](<../../screenshots/Lab 1 screenshots/30c.png>)

#### Access keys, handled safely
Create programmatic credentials for usms-dev-01 and store them without ever risking a commit.
![alt text](<../../screenshots/Lab 1 screenshots/31a.png>)

Confirm Git really is protecting you
![alt text](<../../screenshots/Lab 1 screenshots/31b.png>)

Create a second profile that uses this key
![alt text](<../../screenshots/Lab 1 screenshots/31c.png>)

#### Verification
![alt text](<../../screenshots/Lab 1 screenshots/verification.png>)

## Analysis and Discussion

**What was achieved?** 
The practical set up a working IAM foundation for USMS:
- three groups
- three users
- four policies
- three roles.

**Did the results match expectations?** 
- Yes. Permissions behaved as designed, auditors could only read, developers had their scoped access plus a deny on identity escalation, and the policy simulator confirmed the expected allow/deny outcomes.

**Errors encountered** 
- i got error mostly from the terminal commands, where pasting multi-line commands kept flattening them onto one line, which broke JSON file creation at one point.

**How were the issue resolved?** 
- I solved the error and issues by typing key commands manually (instead of pasting) fixed the flattening issue, and running `pwd` to located the real project path. 

## Reflection
from this practical i learned about aws iam (identity & access management).AWS IAM is about managing authentication and authorization on our cloud service resources which means controlling who can log in and what they are allowed to do once they are in.I also learned users, groups, policies, and roles in IAM. 

So Lastly, even though there were lot of commands, the basic knowledge i got from here is that IAM is about not giving everyone full access instead, giving each user/group/role only the permissions they actually need.

## Conclusion
This practical helped me understand the basics of AWS IAM. I was able to create users, groups, and roles, and attach policies to control what each one could access. Even though the lab had a lot of steps and commands, I now have a basic idea of how IAM works that access should be given through groups and roles, and only the permissions that are actually needed should be granted.

Overall, this practical gave me a starting point to understand how AWS manages access and security, and I know this is something I will need to build on more in future labs.