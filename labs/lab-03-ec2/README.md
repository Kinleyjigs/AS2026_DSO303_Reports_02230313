# Lab 03:  Amazon EC2 and Deploying the USMS Application

## Overview

In Lab 2 I built an empty network. In this lab I put servers into it. I launched a web server (`usms-web-01`) into the public subnet and a database server (`usms-db-01`) into the private subnet. I also gave the web server a fixed public address and an extra data disk, and saved a reusable image of it.

Everything ran on Floci, a local AWS emulator. Floci keeps track of every resource I create, but it doesn't actually boot the servers. Where Floci behaved differently from real AWS, I've noted it under **Floci Limitation**.

---

### Step 1: Resume the environment and load the env files

I started Floci and loaded the settings saved in Labs 1 and 2, so this lab could reuse their subnets, security groups and instance profile.

![Environment loaded](<../../screenshots/Lab 3 screenshots/1.png>)

*Figure 1: Floci is running and all six values from Labs 1 and 2 are loaded.*

### Step 2: Confirm Lab 02's network is intact

I re-ran the Lab 2 verification script to make sure the network was still there before building on it. 32 of 33 checks passed. The one failure is the same one I had at the end of Lab 2: [name the failing check and why it fails]. It doesn't affect anything this lab uses.

### Step 3: Choose an AMI

![AMI selected](<../../screenshots/Lab 3 screenshots/2.png>)

*Figure 2: AMI found with describe-images instead of being hard-coded.*

#### Floci Limitation
By mistake, I also ran Option A (`register-image`), which created an extra image called `usms-course-base`. When I tried to remove it, Floci returned `UnsupportedOperation` for `deregister-image`. On real AWS that command would remove it. The lab uses the Amazon-provided image `ami-0abcdef1234567890`.

### Step 4: Create the key pair and store the private key safely

A key pair is how you log in to a server on real AWS. AWS keeps the public half; the private half is shown only once, at creation. I sent the private key straight into a file so it never appeared on screen, then locked the file with `chmod 600`.

![Key pair created](<../../screenshots/Lab 3 screenshots/3.png>)

*Figure 3: Private key saved straight to a file with chmod 600.*

![Key pair verified](<../../screenshots/Lab 3 screenshots/4.png>)

*Figure 4: AWS keeps only the key's name and fingerprint.*

### Step 5: Prove the private key is git-ignored

Rather than assuming the key was safe, I checked that Git ignores it.

![Key is git-ignored](<../../screenshots/Lab 3 screenshots/5.png>)

*Figure 5: `git check-ignore` shows the `outputs/*` rule covers the private key.*

### Step 6: Write the user-data bootstrap script

User data is a script that runs automatically, as root, the first time a server boots. Mine installs nginx and writes the USMS portal page, so nobody has to log in to set it up. I quoted the heredoc (`<< 'EOF'`) so the variables would only be filled in on the server, not on my laptop.

![User-data script checked](<../../screenshots/Lab 3 screenshots/6.png>)

*Figure 6: The script passes a syntax check and is well under 16 KB.*

### Step 7: Generate a request skeleton and fill it in

`run-instances` has more than fifty options, so I generated the full request as JSON and kept only the fields I needed. A JSON file is easier to review and keep in Git than a very long command.

![Full skeleton](<../../screenshots/Lab 3 screenshots/7.png>)

*Figure 7: The full run-instances request skeleton (about 300 lines).*

![Filled-in request](<../../screenshots/Lab 3 screenshots/8.png>)

*Figure 8: My filled-in request, with real IDs and valid JSON.*

### Step 8: Launch the USMS web server

This one command brought together pieces from three labs: the subnet and security group from Lab 2, the instance profile from Lab 1, and the key pair and script from this lab.

![Web server launched](<../../screenshots/Lab 3 screenshots/9.png>)

*Figure 9: usms-web-01 launched with a single run-instances call.*

### Step 9: Wait for the instance to reach running

Instead of guessing with `sleep`, I used a waiter, which keeps checking until the server is actually running.

![Waiter](<../../screenshots/Lab 3 screenshots/10.png>)

*Figure 10: The waiter exits with code 0 once the instance is running.*

### Step 10: Read the instance back and understand the fields

I pulled the important fields out of `describe-instances` to confirm the server landed where I intended.

![Instance details](<../../screenshots/Lab 3 screenshots/11.png>)

*Figure 11: usms-web-01 is running in the public subnet with usms-app-sg and the instance profile.*

### Step 11: Trace the permission chain from the instance to the policy

I followed the chain from the server to its permissions: instance → instance profile → role → policy.

![Permission chain](<../../screenshots/Lab 3 screenshots/12.png>)

*Figure 12: The chain from usms-web-01 to the USMSStudentDataReadWrite policy.*

The policy gives access to the `usms-student-data` bucket, which doesn't exist yet. That's allowed: a policy describes a resource name, not an object that must already exist. Once Lab 4 creates the bucket, the permission takes effect and the server can upload transcripts without any password or key stored on it.

### Step 12: Prove the user data actually arrived

I tried to read the script back from EC2 and compare it byte for byte with my original file.

![User data check](<../../screenshots/Lab 3 screenshots/13.png>)

*Figure 13:  Floci returns no user data, even for a minimal test launch.*

##### Floci Limitation
Floci didn't store the user data. It returned nothing for usms-web-01, and a test instance launched with only `--user-data` also returned `None`, so the JSON template wasn't the cause. On real AWS, EC2 returns the script base64-encoded, and decoding it gives an exact copy of `user-data.sh`.

### Step 13: Give the web server a stable public address

An auto-assigned public IP changes every time the server is stopped and started. An Elastic IP stays the same, so a DNS name can safely point at it.

![Elastic IP](<../../screenshots/Lab 3 screenshots/14.png>)

*Figure 14: Elastic IP 54.12.10.161 associated, but Floci shows placeholder addresses.*

##### Floci Limitation
Floci allocated Elastic IP 54.12.10.161, but `describe-instances` still showed public IP 127.0.0.1 and private IP 172.20.0.3, which is outside 10.0.1.0/24. On real AWS, the instance's public IP would change to the Elastic IP.

### Step 14: Test the application

I tried to open the portal with `curl`. Since it didn't answer, I checked each part of the network path instead.

![curl and six checks](<../../screenshots/Lab 3 screenshots/15.png>)

*Figure 15: curl times out, but all six reachability checks pass.*

![Seven-link chain](<../../screenshots/Lab 3 screenshots/16.png>)

*Figure 16: The seven links a request passes through to reach the server.*

For a browser to reach the server, all seven of these must be true: the internet gateway is attached, the route table points to it, the network ACL allows the traffic, the security group allows port 80, the server has a public IP, the server is running, and a program is listening on port 80. I could verify the first six. The seventh can't be checked on Floci.

##### Floci Limitation
Floci doesn't boot an operating system, so nginx never runs and nothing listens on port 80. On real AWS, curl would return the USMS portal page. Check 6 also showed a custom network ACL (`IsDefault = False`) on the public subnet, where the lab expected the default one.

### Step 15: Create and attach a data volume

The root disk is deleted when a server is terminated, so student data needs its own disk. I created an 8 GiB volume in the same Availability Zone as the server and attached it.

![Volume attached](<../../screenshots/Lab 3 screenshots/17.png>)

*Figure 17: usms-web-data-vol attached at /dev/sdf.*

![Volumes compared](<../../screenshots/Lab 3 screenshots/18.png>)

*Figure 18: The root volume is deleted on termination; the data volume is not.*

#### Testing the AZ constraint

I created a volume in us-east-1b and tried to attach it to the server in us-east-1a.

![AZ test](<../../screenshots/Lab 3 screenshots/19.png>)

*Figure 19: Cross-AZ attach rejected; the test volume was then deleted.*

Floci rejected it with `InvalidParameterValue`. Real AWS rejects it too, but with `InvalidVolume.ZoneMismatch`. A volume lives in one Availability Zone and can't attach to a server in another.

### Step 16: Launch the database-tier instance into the private subnet

The database server goes in the private subnet with no public address. I deliberately didn't give it an instance profile, because it has no reason to use S3, and extra permissions are a security risk.

![DB instance](<../../screenshots/Lab 3 screenshots/20.png>)

*Figure 20: usms-db-01 in the private subnet with usms-db-sg, no public IP and no profile.*

### Step 17: Prove the two tiers are wired the way you think

Floci doesn't enforce security groups, so I couldn't show a blocked connection. Instead, I read back the settings that would block it on real AWS.

![Two-tier wiring](<../../screenshots/Lab 3 screenshots/21.png>)

*Figure 21: Checkpoint 5 — the database only accepts port 5432 from the web tier's security group.*

The private subnet's internet route goes through the NAT gateway, not the internet gateway. Traffic can go out, but nothing from the internet can come in, even if someone opened the database's security group later.

### Step 18 — Stop and start the web server, and watch which address moves

I stopped and restarted the web server to check which addresses stay the same.

![Stop and start](<../../screenshots/Lab 3 screenshots/22.png>)

*Figure 22: The Elastic IP and private IP are unchanged after a stop and start.*


#### A second web server in the other AZ
I copied the JSON template, changed only the subnet and the name, and launched `usms-web-02` in us-east-1b.

![Second web server](<../../screenshots/Lab 3 screenshots/23.png>)

*Figure 23: Two web servers in two Availability Zones from almost identical templates.*

### Step 19: Prove the compute layer survives a restart

I saved a list of my servers, restarted Floci, and looked them up again by tag. The two lists matched exactly.

![Persistence](<../../screenshots/Lab 3 screenshots/24.png>)

*Figure 24: Checkpoint 6 — instances, volumes and Elastic IPs all survive a Floci restart.*

### Step 20 — Create an AMI from the configured instance

I saved the web server as a "golden" image so future servers can start already configured. Lab 8 will use it for Auto Scaling.

![Golden AMI](<../../screenshots/Lab 3 screenshots/25.png>)

*Figure 25: usms-web-golden image created and available.*

| | User data | AMI |
|---|---|---|
| Boot time | Slow; installs everything at each launch | Fast; everything is already there |
| Patching | Always gets the latest packages | Frozen until rebuilt |
| Reviewability | Script is readable in Git | Contents are hidden |

In practice, the two are usually combined: an AMI for the slow, stable parts, plus a short user-data script for settings that differ per environment.

### Step 21: Audit what this lab created

I listed every USMS resource to check that each one is named and tagged.

![Audit](<../../screenshots/Lab 3 screenshots/26.png>)

*Figure 26: All USMS instances, volumes, Elastic IPs and images, named and tagged.*

The image list also shows `usms-course-base`, the extra image from Step 3 that Floci won't let me remove.


### Step 22: Write configs/lab-03.env

I saved the IDs that later labs need. They were looked up from Floci, not copied from shell variables, and the file contains no secrets.

![lab-03.env](<../../screenshots/Lab 3 screenshots/27.png>)

*Figure 28: lab-03.env, with every value filled in and no secrets.*

### 9.2: Build scripts/utilities/verify-lab-03.sh

I wrote a script that checks every Lab 3 resource and setting in one run.

![Verification](<../../screenshots/Lab 3 screenshots/28.png>)

*Figure 29: verify-lab-03.sh results: PASS=__ FAIL=__.*

The check "usms-web-01 has user data stored" passes, but for the wrong reason. Floci returns the word `None`, and the script only checks that the answer isn't empty. A stricter check would also reject `None`.


---

## Floci vs Real AWS: what I ran into

| Area | What Floci did | What real AWS does |
|---|---|---|
| Deleting an image | `deregister-image` not supported | Removes the image |
| User data | Not stored; returned `None` | Stored and returned base64-encoded |
| IP addresses | Placeholders (127.0.0.1, 172.20.0.3) | Private IP from the subnet; public IP becomes the Elastic IP |
| Running the server | No OS boots; curl times out | Real VM boots, nginx serves the page |
| Security groups | Stored but not enforced | Every packet is filtered |
| Cross-AZ volume attach | Rejected with `InvalidParameterValue` | Rejected with `InvalidVolume.ZoneMismatch` |
| Speed and cost | Instant and free | 30–60 s to start; every hour is billed |

## What I observed vs what I reasoned about

**Seen directly:** servers placed in the right subnets with the right security groups, the 

instance → profile → role → policy chain, the AZ rule for volumes, 
the data volume surviving termination settings, the image record, and everything surviving a Floci restart.

**Reasoned about but not seen:** nginx running, the user-data script executing, the server fetching credentials, security groups blocking traffic, and the public IP being released on stop.

## Reflection

This lab helped me understand how the resources from earlier labs work together to launch a working server without storing passwords. I also learned how to check connection problems step by step and why each check is important. The most important lesson was that a command finishing without errors does not always mean it worked as expected, so checking the results is necessary.
