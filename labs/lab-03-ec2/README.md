


### Step 1: Resume the environment and load three env files
![alt text](<../../screenshots/Lab 3 screenshots/1.png>)
Figure 1: Floci is running and the Lab 01/Lab 02 env files are loaded, subnets, security groups, instance profile and AZ are all populated.

### Step 2: Confirm Part A's network is intact
The network part is still there, i got the test pass 32/33 the 1 fail is still there from lab 2.

### Step 3: Choose an AMI

![alt text](<../../screenshots/Lab 3 screenshots/2.png>)

### Step 4 - Create the key pair and store the private key safely

A key pair is how you would log in to the instance on real AWS. AWS keeps the public half and injects it into the instance at first boot; the private half is shown to you exactly once, at creation, and can never be retrieved again. Losing it means losing shell access to every instance launched with it.

![alt text](<../../screenshots/Lab 3 screenshots/3.png>)

verify 

![alt text](<../../screenshots/Lab 3 screenshots/4.png>)

### Step 5 - Prove the private key is git-ignored
![alt text](<../../screenshots/Lab 3 screenshots/5.png>)

### Step 6 - Write the user-data bootstrap script
The USMS student portal has to exist on the instance without anyone logging in to put it there. A user-data script is how that happens: cloud-init runs it as root at first boot

![alt text](<../../screenshots/Lab 3 screenshots/6.png>)

### Step 7 - Generate a request skeleton and fill it in

Command - part 1, look at the shape
![alt text](<../../screenshots/Lab 3 screenshots/7.png>)

Command - part 2, write the request we actually want
![alt text](<../../screenshots/Lab 3 screenshots/8.png>)


### Step 8 - Launch the USMS web server

![alt text](<../../screenshots/Lab 3 screenshots/9.png>)

usms-web-01 launched with a single run-instances call combining the Lab 02 subnet and security group, the Lab 01 instance profile, and this lab's key pair and user data.

### Step 9 — Wait for the instance to reach running
![alt text](<../../screenshots/Lab 3 screenshots/10.png>)

aws ec2 wait instance-running polls describe-instances until the instance is running and exits 0, instead of guessing with sleep.

### Step 10 - Read the instance back and understand the fields
![alt text](<../../screenshots/Lab 3 screenshots/11.png>)

Checkpoint 2 — usms-web-01 is running as a t3.micro in usms-public-subnet-a (10.0.1.0/24) with an auto-assigned public IP, usms-app-sg, usms-app-key and the usms-ec2-app-profile instance profile.

### Step 11 - Trace the permission chain from the instance to the policy
![alt text](<../../screenshots/Lab 3 screenshots/12.png>)

The permission chain traced from usms-web-01 to its instance profile, to usms-ec2-app-role, to the USMSStudentDataReadWrite policy

### Step 12 - Prove the user data actually arrived
![alt text](<../../screenshots/Lab 3 screenshots/13.png>)

Figure: describe-instance-attribute returns no userData for usms-web-01, and a minimal test launch with only --user-data also returns None. This shows the Floci build does not store user data (a Floci limitation, not a launch error). On real AWS the attribute returns the base64-encoded script and the diff would be empty.


##### Floci Limitation 
Floci did not store user data. describe-instance-attribute returned no UserData for usms-web-01, and a test instance launched with only --user-data also returned None, so the problem was not the --cli-input-json merge. The byte-for-byte proof could not be completed. On real AWS, the CLI base64-encodes the script, EC2 stores it, and decoding it gives a file identical to user-data.sh.”

### Step 13 - Give the web server a stable public address

![Elastic IP associated with usms-web-01](<../../screenshots/Lab 3 screenshots/14.png>)

Elastic IP 54.12.10.161 was allocated and associated with usms-web-01, but Floci still shows placeholder addresses on the instance (public 127.0.0.1, private 172.20.0.3).

##### Floci Limitation
Floci allocated Elastic IP 54.12.10.161, but describe-instances still showed public IP 127.0.0.1 and private IP 172.20.0.3 (outside 10.0.1.0/24). On real AWS, the instance's public IP would change to the Elastic IP.

### Step 14 - Test the application

![curl timeout and six reachability checks](<../../screenshots/Lab 3 screenshots/15.png>)

curl times out because Floci doesn't run a real server, but the six checks show the network setup for reaching the web server is correct.

##### Floci Limitation
Floci does not boot an operating system, so no web server (nginx) is listening on port 80. On real AWS, curl would return the USMS Student Portal page.

![7-link chain](<../../screenshots/Lab 3 screenshots/16.png>)

curl times out because Floci doesn’t run a real server, but the six checks show the network setup for reaching the web server is correct.

### Step 15 - Create and attach a data volume

![AttachVolume table](<../../screenshots/Lab 3 screenshots/17.png>)

![describe-volumes](<../../screenshots/Lab 3 screenshots/18.png>)
Figure 17: usms-web-data-vol (8 GiB gp3) created in the instance's own AZ and attached at /dev/sdf; unlike the root volume (DeleteOnTermination True) it survives instance termination (False)


###  test the AZ constraint

![test the AZ constraints](<../../screenshots/Lab 3 screenshots/19.png>)

Figure 18: Attaching a us-east-1b volume to the us-east-1a web server is rejected, which proves an EBS volume can only attach to an instance in the same Availability Zone. The test volume was then deleted.

### Step 16 - Launch the database-tier instance into the private subnet
![database-tier instance](<../../screenshots/Lab 3 screenshots/20.png>)

Figure 19:usms-db-01 launched into usms-private-subnet-a (10.0.3.0/24) with usms-db-sg, no public IP and deliberately no instance profile.

### Step 17 - Prove the two tiers are wired the way you think
![two tiers](<../../screenshots/Lab 3 screenshots/21.png>)

Figure 19: usms-db-01 sits in the private subnet with no public address and no profile; usms-db-sg admits TCP 5432 only from usms-app-sg (by group reference), and the private route table's default route targets the NAT gateway, not the internet gateway.

### Step 18 - Stop and start the web server, and watch which address moves
![web server](<../../screenshots/Lab 3 screenshots/22.png>)
Figure 20: Stop/start of usms-web-01 — the private IP (10.0.1.x) and the Elastic IP are unchanged after restart, while [Floci did / did not] clear the public address during the stopped state.


![web server](<../../screenshots/Lab 3 screenshots/23.png>)

Figure 21: usms-web-02 launched into usms-public-subnet-b (us-east-1b) from a copy of the JSON template — the reviewable diff is just the subnet and name — giving two web instances across two AZs.

### Step 19 - Prove the compute layer survives a restart

![compute layer](<../../screenshots/Lab 3 screenshots/24.png>)


Figure 22: Checkpoint 6 — after stopping and restarting the Floci container, instances found by tag have identical IDs, subnets and security groups; EBS volumes (4) and Elastic IPs (2) are still present.

### Step 20 — Create an AMI from the configured instance

![AMI](<../../screenshots/Lab 3 screenshots/25.png>)

Figure 23: Checkpoint 7 — golden AMI usms-web-golden created from usms-web-01 with --no-reboot, state available, tagged Project=USMS for use in Lab 08's launch template.


### Step 21 — Audit what this lab created

![audit](<../../screenshots/Lab 3 screenshots/26.png>)

Figure 24: Audit of all USMS compute resources — instances, EBS volumes, Elastic IPs and the golden AMI — every one named and tagged Project=USMS.

### Step 22 — Write configs/lab-03.env
![configs](<../../screenshots/Lab 3 screenshots/27.png>)

Figure 26: configs/lab-03.env generated by lookup (not from shell variables), containing only resource IDs and no secrets, with every value populated.

### Step 23 - Commit







