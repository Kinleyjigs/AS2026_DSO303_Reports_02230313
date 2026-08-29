# Lab 2 VPC: Virtual Private Cloud and Networking

## Aim 
To design and build a secure, multi-tier VPC for the USMS system using the AWS CLI, 
including public and private subnets, routing, an internet gateway, a NAT gateway, 
security groups, a network ACL, and an S3 gateway endpoint and to verify the network 
is correctly isolated, tagged, and persists across a restart.

## Introduction
A VPC is an isolated private network within AWS, and every resource that needs 
networking must live inside one. This lab builds a VPC entirely from the AWS CLI, 
capturing every resource ID into shell variables and later into a config file instead 
of copying values by hand. It covers CIDR addressing, the difference between public and 
private subnets (which comes down to routing, not naming), the two AWS firewall layers 
security groups (stateful, instance-level) and network ACLs (stateless, subnet-level)
and how a NAT gateway and an S3 gateway endpoint control what traffic can leave a 
private subnet and where it goes.

## Use Case
USMS is a university student management system with three requirements this network is 
built around:
- A **web tier** reachable from the public internet.
- A **data tier** (transcripts, enrolment records) that must never be reachable from the 
  internet.
- The data tier must still be able to fetch OS updates **outbound only**.

A public subnet serves the web tier, a private subnet holds the data tier, and a NAT 
gateway gives the private subnet one-way outbound access. The network spans two 
Availability Zones so it can tolerate the loss of one.

## System Architecture / Design

**USMS VPC architecture**
![alt text](<../../screenshots/Lab 2 screenshots/architect.png>)

The diagram shows the USMS VPC layout public subnets hosting the web tier and NAT gateway, private subnets hosting the database and NACL, internet access routed through the 
gateway, and S3 reached via the gateway endpoint instead of the public internet.

**AWS Academy VPC and NAT gateway pattern**
![alt text](<../../screenshots/Lab 2 screenshots/NAT.png>)

## Evidence and Results
#### Step 1 Resume the environment
Before we start with this VPC lab we should be doing the lab 1 IAM. here the lab expects the part B of lab 1 to be done 
![alt text](<../../screenshots/Lab 2 screenshots/1.png>)

Verify floci running by deleting the running docker floci image and running it again.
![alt text](<../../screenshots/Lab 2 screenshots/2.png>)

#### Step 2 Load the previous lab's environment and confirm your identity
In this lab we needs three things Lab 1 produced: 
- the developer role's name
- the developer user's name
- Our account ID. 

![alt text](<../../screenshots/Lab 2 screenshots/3.png>)

Here i have loaded the Lab1 environment variables and verified the AWS account before running commands.


![alt text](<../../screenshots/Lab 2 screenshots/4.png>)

- a subnet's CIDR must be a subset of the VPC's, must not overlap any other subnet in that VPC, and can never be changed after creation

#### Step 3 Assume the developer role and create the VPC


Command part 1, read the policy before you rely on it

![alt text](<../../screenshots/Lab 2 screenshots/5.png>)

Command part 2, assume the role
![alt text](<../../screenshots/Lab 2 screenshots/6.png>)

Command part 3, create the VPC
![alt text](<../../screenshots/Lab 2 screenshots/7.png>)

#### Step 4 Restore your normal identity
usms-developer-role was created with a one-hour maximum session duration. If you keep these credentials for the whole lab, they will expire somewhere around Step 15 and you will get ExpiredToken errors that look nothing like their cause. Hand them back now.

![alt text](<../../screenshots/Lab 2 screenshots/8.png>)


#### Step 5 Enable DNS support and DNS hostnames

![alt text](<../../screenshots/Lab 2 screenshots/9.png>)
- No output. Both commands print nothing and exit 0. Silence from modify-* calls is normal; that is why the verify step below is not optional.

![alt text](<../../screenshots/Lab 2 screenshots/10.png>)

#### Step 6 Create and attach the internet gateway
An internet gateway is the VPC's door to the internet it forwards traffic in/out and does 1:1 NAT between an instance's private and public IP. Nothing works until it's created, attached to the VPC, and referenced in a route table three separate steps, and skipping any one looks the same from inside an instance (no internet).

![alt text](<../../screenshots/Lab 2 screenshots/11.png>)

Verify
![alt text](<../../screenshots/Lab 2 screenshots/12.png>)

#### Step 7 Create the public subnet in us-east-1a
In here we are just creating a subnet, a small slice of the VPC's address space (10.0.1.0/24) which is placed in availability zone us-east-1a.

We give it a tag saying "this is public" then the command saves its ID into a variable PUBLIC_SUBNET_A_ID so that we can refer later.
![alt text](<../../screenshots/Lab 2 screenshots/13.png>)


Then we verify by checking whether it was created correctly.So it exists and has 251 usable IPs.
![alt text](<../../screenshots/Lab 2 screenshots/14.png>)

#### Step 8 Turn on auto-assign public IPv4 for the public subnet
we are flipping the switch on that subnet so any instance launched into it automatically gets a public IP address (without this, it would only get a private one).

![alt text](<../../screenshots/Lab 2 screenshots/15.png>)

#### Step 9 Create the private subnet in us-east-1a
Creates the second subnet (10.0.3.0/24), this one for the private/data tier. 
Here the difference is just the CIDR and tags, and i did't turn on auto-assign public IP.
![alt text](<../../screenshots/Lab 2 screenshots/16.png>)

Then verify by listing both the subnets side by side in a table.
![alt text](<../../screenshots/Lab 2 screenshots/17.png>)

#### Step 10 Create the public route table and the default route

Creates a route table and adds a rule: "anything not matching a more specific route (0.0.0.0/0) the send to the internet gateway." This is the actual step that makes internet access possible.

![alt text](<../../screenshots/Lab 2 screenshots/18.png>)

Verify 
![alt text](<../../screenshots/Lab 2 screenshots/19.png>)

#### Step 11 Associate the public subnet with the public route table
Attaches (associates) that route table to the public subnet. Without this, the route table exists but affects nothing. the subnet would silently fall back to the VPC's default route table (no internet).

![alt text](<../../screenshots/Lab 2 screenshots/20.png>)

#### Step 12 Create the private route table and associate the private subnet
create a separate route table (usms-private-rt) and associate it with the private subnet. 
we are doing this avoids accidentally inheriting a route table.

![alt text](<../../screenshots/Lab 2 screenshots/21.png>)

#### Step 13 Prove the two subnets are actually different
It reads back both subnets' actual route tables to confirm that one points to the internet gateway (public) and the other has no default route at all (private). This is the real evidence that "public" vs "private" isn't just a name/tag, it's the routing.

![alt text](<../../screenshots/Lab 2 screenshots/22.png>)

#### Step 14 Create the application security group
Creates the security group for the app/web servers (usms-app-sg). Opens ports 80 (HTTP) and 443 (HTTPS) to everyone, and port 22 (SSH) only from inside the VPC, not the whole internet.

![alt text](<../../screenshots/Lab 2 screenshots/23.png>)

#### Step 15 Create the database security group, sourced from the application group
Here we creates the security group for the database (usms-db-sg). Which allows PostgreSQL (port 5432), but only from instances in usms-app-sg, not from any IP range. This way, if the app tier's address changes, the rule still works automatically.

create the group
![alt text](<../../screenshots/Lab 2 screenshots/24.png>)

write the rule as a JSON document
![alt text](<../../screenshots/Lab 2 screenshots/25.png>)

verify 
![alt text](<../../screenshots/Lab 2 screenshots/26.png>)

#### Step 16 Read the groups back, and understand what stateful means
Reads back both security groups together and walks through a full request to show how few rules we actually needed, because security groups are stateful (return traffic is auto-allowed, no extra rules needed).

![alt text](<../../screenshots/Lab 2 screenshots/27.png>)

#### Step 17 Explore the default network ACL, then create a private one
Looks at the subnet-level firewall (Network ACL).first we checks the default one (allows everything), then creates a custom private NACL with specific allow rules (DB traffic in, HTTPS out, plus the return/ephemeral-port rule) as a second layer of defense on top of security groups.

![alt text](<../../screenshots/Lab 2 screenshots/28.png>)

verify 
![alt text](<../../screenshots/Lab 2 screenshots/29.png>)

#### Step 18 Associate the private NACL with the private subnet
Attaches (associates) the new private NACL to the private subnet, replacing its default NACL, since every subnet must have one and we can't just "add" a second.
![alt text](<../../screenshots/Lab 2 screenshots/30.png>)


#### Step 19 Give the private subnet outbound internet access with a NAT gateway
Creates a NAT gateway (with an Elastic IP) in the public subnet, this lets private-subnet instances reach the internet for outbound-only traffic (like OS updates), without being reachable from outside.
![alt text](<../../screenshots/Lab 2 screenshots/31.png>)

#### Step 20 Point the private route table at the NAT gateway
Points the private route table's default route (0.0.0.0/0) at the NAT gateway.

![alt text](<../../screenshots/Lab 2 screenshots/32.png>)

#### Step 21 Create the S3 gateway endpoint
Creates an S3 gateway endpoint so private instances can reach S3 directly over AWS's internal network instead of routing through the NAT gateway/internet, faster and cheaper.
![alt text](<../../screenshots/Lab 2 screenshots/33.png>)

#### Step 22 Audit your tags
Audits all the resources created in this lab to confirm that they are properly tagged Project=USMS  a sanity check, not a build step.
![alt text](<../../screenshots/Lab 2 screenshots/34.png>)

#### Step 23 Prove the network survives a restart
Restarts the environment and re-checks that everything (VPC, subnet count, security group count) still exists afterward, proving the setup actually persists and wasn't just "in memory."
![alt text](<../../screenshots/Lab 2 screenshots/35.png>)

#### Step 24 Write configs/lab-02.env
Saves all the resource IDs (VPC, subnets, security groups, etc.) into configs/lab-02.env so the next lab can reuse them without having to remember or recreate anything.

#### Verifications 
The verification script against all Lab 02 resources shows that 32/33 pass. The one failure 
(`usms-db-sg` group reference) is a confirmed Floci limitation where group-to-group security 
rules don't persist, not a configuration mistake, I tested four different valid syntaxes but 
still got the same error.

![alt text](<../../screenshots/Lab 2 screenshots/36.png>)


## Reflection
1. What did you learn?
from this lab i learned how to build a VPC from the CLI instead of clicking through the console, which is how I did a similar lab in AWS Academy before. I also learned how to set up public and private subnets, an internet gateway, security groups, and NACLs by hand.I also learned that security groups are stateful and sit on the instance, NACLs are stateless and sit on the subnet.

2. What challenges did you encounter?
The verification step (Step 9) was the hardest part. I started at 28/33 and had to debug each failure one by one. a broken db-sg rule, an unattached NACL, empty config values, and a secret file tracked by git. I fixed four of the five and got to 32/33. 

The one I couldn't fix was the db-sg rule — I tried four different valid CLI approaches, including recreating the security group after a full container restart, and none of them stuck. Turned out to be a Floci bug, not something wrong with my commands.

3. How would you apply this in a real-world environment?
I would use public and private subnets to separate web servers from databases. NAT gateways can provide controlled internet access for private resources, while S3 endpoints can provide secure and efficient access to S3. I would also keep resource IDs organized and secrets out of Git.

4. What additional concepts would you like to explore?
I'd like to look into VPC peering and Transit Gateway next, since real setups usually have more than one VPC that need to talk to each other. I'm also curious about interface endpoints, and using Terraform instead of writing out CLI commands every time.

## Conclusion 
From this Lab I gained a practical experience in creating a VPC with public and private subnets, an internet gateway, NAT gateway, security groups, and network ACLs using the AWS CLI, and verified the setup with the provided verification script.
This lab shows the importance of network segmentation in cloud computing and showed how a VPC forms the foundation of network security on AWS.




