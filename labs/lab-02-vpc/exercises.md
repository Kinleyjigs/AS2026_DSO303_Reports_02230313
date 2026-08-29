## Exercise 1 Basic: a third public subnet

**Create usms-public-subnet-c**
![alt text](<../../screenshots/Lab 2 screenshots/exercise1a.png>)
Creates `usms-public-subnet-c` in `us-east-1c` with CIDR `10.0.5.0/24`, tagged consistently 
with the existing subnets via `--tag-specifications`, capturing the new subnet ID directly 
into a shell variable.


**Enable auto-assign public IP and associate the route table**
![alt text](<../../screenshots/Lab 2 screenshots/exercise1b.png>)
Enables auto-assign public IPv4 on the new subnet and associates it with `usms-public-rt`, 
confirming both steps succeeded.

**Verification**
![alt text](<../../screenshots/Lab 2 screenshots/exercise1c.png>)
Confirms `usms-public-subnet-c` exists in `us-east-1c` with the correct CIDR and 
auto-assign setting, and that `usms-public-rt` now has three subnet associations instead 
of two.

## Exercise 2 Intermediate: a bastion security group

**Create usms-bastion-sg**
![alt text](<../../screenshots/Lab 2 screenshots/exercise2a.png>)
Creates `usms-bastion-sg` for a future jump host, allowing inbound SSH only from a single 
admin workstation address (`103.133.216.195/32`), with a description explaining the rule.

**Swap usms-app-sg's SSH rule to reference the bastion**
![alt text](<../../screenshots/Lab 2 screenshots/exercise2b.png>)
Adds a group-referenced SSH rule on `usms-app-sg` sourced from `usms-bastion-sg`, then 
removes the old `10.0.0.0/16` CIDR-based SSH rule. Verification confirms `usms-app-sg` 
now has exactly one SSH rule, sourced from the bastion security group.

## Exercise 3 Problem solving: prove a claim about the network

![alt text](<../../screenshots/Lab 2 screenshots/exercise3.png>)
Writes `scripts/utilities/lab-02-network-report.sh`, which classifies every subnet in 
`usms-vpc` as PUBLIC, PRIVATE, or ISOLATED based on its actual route table, not its name 
or tags. Uses `BASH_SOURCE` to resolve paths, so it runs correctly from any directory verified by running it from the repo root, a nested folder, and the home directory, all producing identical output.

## Exercise 4 Challenge: design and defend

![alt text](<../../screenshots/Lab 2 screenshots/exercise4.png>)
Creates `usms-exam-sg`, allowing inbound HTTPS from the campus VPN range (`10.10.0.0/16`) 
only. Adds a group-referenced rule to `usms-db-sg` so the exam-results service can read 
the transcripts database. Full design rationale subnet placement, NACL reasoning, NAT 
gateway cost trade-off, and deletion plan is documented in `labs/lab-02-vpc/exercises.md`.

## Exercise 5 Integration: complete the second Availability Zone

**Delete the old subnet and assume the role**

![alt text](<../../screenshots/Lab 2 screenshots/exercise5a.png>)
Deleted the earlier `usms-private-subnet-b` since it wasn't created under the assumed role. Then assumed `usms-developer-role` and confirmed the switch with `get-caller-identity` the ARN now shows `assumed-role/usms-developer-role` instead of `root`.

**Back to my normal identity**

![alt text](<../../screenshots/Lab 2 screenshots/exercise5b.png>)
I unset the assumed-role credentials and confirmed with `get-caller-identity` that I am back to `root`. I want to drop the elevated role's credentials as soon as I am done with them, so nothing later in the session accidentally runs with more access than it should.

**Final verification**
![alt text](<../../screenshots/Lab 2 screenshots/exercise5c.png>)
I re-ran the verify script after regenerating `configs/lab-02.env`. 32/33 pass, with the one failure being the same `usms-db-sg` Floci bug from earlier not anything new.