
## Step 12 — Create the floci AWS CLI profile
![alt text](<../../screenshots/Screenshot 2026-08-21 at 11.37.06 PM.png>)

What the command does

- aws configure set <key> <value> --profile <name> writes one setting into the profile files, creating them if needed. Credentials go to ~/.aws/credentials, everything else to ~/.aws/config.
- endpoint_url is the line that redirects all services in this profile to Floci. Without it the CLI would contact real AWS.
- test/test are dummy credentials. Floci accepts any non-empty values by default

![alt text](<../../screenshots/Screenshot 2026-08-21 at 11.38.48 PM.png>)


```
aws configure list --profile floci
```

![alt text](<../../screenshots/Screenshot 2026-08-21 at 11.41.14 PM.png>)

Read the output

Account = 000000000000 — Floci's fixed dummy account number. Real AWS accounts are real 12-digit numbers. Seeing all zeros is your proof you are not on real AWS.
Arn — an Amazon Resource Name, explained fully in Step 16.

![alt text](<../../screenshots/Screenshot 2026-08-21 at 11.44.27 PM.png>)

## Step 14 — Prove isolation from real AWS, and prove persistence
14.2 Isolation, Test 2 — inspect the actual URL the CLI used
![alt text](<../../screenshots/Screenshot 2026-08-21 at 11.46.30 PM.png>)


14.3 Isolation, Test 3 — stop the container
![alt text](<../../screenshots/Screenshot 2026-08-21 at 11.48.24 PM.png>)

14.4 Persistence — the test that actually matters
![alt text](<../../screenshots/Screenshot 2026-08-21 at 11.49.53 PM.png>)

Clean up the marker & 14.5 Exit codes
![alt text](<../../screenshots/Screenshot 2026-08-21 at 11.51.25 PM.png>)

**Floci Limitation — identity is not really authenticated**
    
    Real AWS verifies your signature cryptographically and rejects wrong credentials. Floci accepts any non-empty credentials by default, and reports you as the account root user. So get-caller-identity in Floci confirms connectivity, not authentication.

## Step 15 — Storage diagnostics, README, and commit Part A
![alt text](<../../screenshots/Screenshot 2026-08-21 at 11.56.06 PM.png>)


# PART B — Building the IAM Foundation (Steps 16–33)

## Step 16 — IAM concepts and the anatomy of an ARN
#### Purpose
Understand the vocabulary before typing commands. Five minutes here saves an hour of confusion later.

#### Floci Limitation — policies are stored, not enforced (by default)

    This is the most important Floci caveat in this lab.

    Real AWS evaluates every request against IAM policies and returns AccessDenied when they do not permit it. Floci, by default, accepts any non-empty credentials and does not authorize requests against your IAM policies unless stricter authentication is explicitly enabled.

    What this means for you: everything you write in this lab is stored, retrievable and syntactically validated — you are learning real IAM authoring. But you generally will not see an AccessDenied in Floci simply because a policy was too narrow. Step 32 shows the policy simulator as the closest available substitute, and Section 12 lists exactly which parts of this lab are "conceptual / real AWS" rather than "enforced by Floci".

    Write every policy as if it were enforced. In a real account it will be.

## Step 17 — Inspect the empty IAM account

![alt text](<../../screenshots/17.png>)

## Step 18 — Create the IAM groups
![alt text](<../../screenshots/18a.png>)

create-group creates an empty IAM group. A group has no permissions and no members at birth — it is purely a container. Note there is no --region: IAM is global.

verify
![alt text](../../screenshots/18b.png)

## Step 19 — Create the IAM users and capture their ARNs

Purpose

Create three users, and learn the single most important AWS CLI habit: never copy an ID by hand.

Concept: why capture output into variables

Copying arn:aws:iam::000000000000:user/usms-dev-01 by hand from the screen into the next command is slow and error-prone. Instead, ask the CLI for exactly one value and store it in a shell variable

![alt text](<../../screenshots/19a.png>)

Verify
![alt text](<../../screenshots/19b.png>)

## Step 20 — Add users to groups
![alt text](<../../screenshots/20.png>)

## Step 21 — Explore and attach an AWS managed policy
Explore what is available
![alt text](<../../screenshots/21.png>)

## Step 22 — Write your first customer managed policy
![alt text](<../../screenshots/22a.png>)

![alt text](<../../screenshots/22b.png>)

## Step 23 — Write the S3 data policy (used for real in Lab 4)
Write the policy that will govern student transcript storage, and get the bucket-vs-object ARN distinction right.

![alt text](../../screenshots/23.png)

![alt text](../../screenshots/23b.png)

## Step 24 — Use --generate-cli-skeleton to discover parameters
![alt text](../../screenshots/24.png)

## Step 25 — Add an inline policy (self-service credentials)

![alt text](../../screenshots/25.png)

## Step 26 — Inspect what you have built
 A.Everything about one user
![alt text](../../screenshots/26a.png)

 B. Read the actual policy JSON back out
![alt text](../../screenshots/26b.png)

## Step 27 — Policy versions
![alt text](../../screenshots/27.png)

## Step 28 — Create a role for EC2, with a trust policy
![alt text](../../screenshots/28a.png)

What the command does

--assume-role-policy-document is the trust policy — the "who may become me" document. This flag name is genuinely confusing; remember it is the trust policy, not the permissions policy.
The role starts with zero permissions. Trust and permissions are completely separate.


give permission 
![alt text](../../screenshots/28b.png)

Create the instance profile & verify 
![alt text](../../screenshots/28c.png)

## Step 29 — Create the Lambda execution role
create lumbda function and verify 
![alt text](../../screenshots/29.png)

## Step 30 — A role for humans, and temporary credentials with STS
Create the role with an account-principal trust policy

![alt text](../../screenshots/30a.png)

Give the developers group permission to assume it
![alt text](../../screenshots/30b.png)

Assume the role
![alt text](../../screenshots/30c.png)

## Step 31 — Access keys, handled safely
Create programmatic credentials for usms-dev-01 and store them without ever risking a commit.
![alt text](../../screenshots/31a.png)

Confirm Git really is protecting you
![alt text](../../screenshots/31b.png)

Create a second profile that uses this key
![alt text](../../screenshots/31c.png)

## Step 32 — Test permissions with the policy simulator
![alt text](../../screenshots/32.png)

