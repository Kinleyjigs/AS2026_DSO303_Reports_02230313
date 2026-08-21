1. Aim / Objective¶
State the objective(s) of this practical exercise.

Example:
To create and manage IAM users, groups, and policies using the AWS CLI and verify access permissions.

2. Introduction¶
Provide a brief overview of the AWS service explored during this practical (1 paragraph).

Include:

Purpose of the service
Key features
Importance in cloud computing
Typical applications
3. Use Case¶
Describe where this AWS service is commonly used.

Example

Managing employee identities and permissions using AWS IAM.
Hosting scalable web applications using Amazon EC2.
Storing application assets using Amazon S3.
4. System Architecture / Design (If Applicable)¶
Insert a system architecture or workflow diagram illustrating how the AWS services interact.

The diagram should clearly indicate:

AWS services used
User interactions
Resource relationships
Data flow
Insert architecture diagram here

5. Implementation Procedure¶
Breifly Document each step performed during the practical.

6. Results and Evidence¶
6.1 CLI / SDK Output¶
Include screenshots showing:

Commands executed
Successful outputs
SDK program execution (if applicable)
Insert screenshot(s) here

6.2 AWS Management Console Verification¶
Provide screenshots from the AWS Console confirming successful resource creation or configuration and give one line explanation of the action performed.

Examples include:

IAM Users
EC2 Instances
S3 Buckets
Lambda Functions
VPC Resources
CloudWatch Dashboards
Insert screenshot(s) here

7. Analysis and Discussion¶
Discuss the outcomes of the practical.

Include:

What was achieved?
Did the results match the expected outcome?
Were any errors encountered?
How were the issues resolved?
What observations were made during implementation?

8. Reflection¶
Reflect on your learning experience by answering the following questions:

What did you learn about this AWS service?
What challenges did you encounter?
How would you apply this service in a real-world cloud environment?
What additional concepts or features would you like to explore?

9. Conclusion¶
Summarise the practical in one or two paragraphs.

Include:

Whether the objectives were achieved
Key concepts learned
Skills developed
Importance of the AWS service
10. Appendix (Optional)¶
Include links to any supplementary materials, such as:

Complete source code
JSON policy files
CloudFormation templates
Terraform configurations
Additional screenshots
Error logs
Configuration files
Submission Checklist¶
Before submitting your report, ensure that you have included:

Aim/Objectives clearly stated
Introduction provided
Real-world use case described
System architecture included (if applicable)
All implementation steps documented
CLI/SDK screenshots included
AWS Console verification screenshots included
Analysis and discussion completed
Reflection completed
Conclusion written
Appendix attached (if applicable)


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














