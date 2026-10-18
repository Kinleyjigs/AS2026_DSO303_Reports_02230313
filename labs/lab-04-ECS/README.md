# Lab 04 - Amazon ECS
---

## Aim / Objective

## Introduction

## Use Case¶

## System Architecture / Design

## Implementation Procedure

## Results and Evidence
### Step 1 - Resume the environment and load three env files¶
### Step 2 - Confirm Labs 2 and 3 are still intact

### Step 3 - Probe what this Floci build actually supports
Find out whether your build supports ECS and Application Auto Scaling.

![alt text](<../../screenshots/Lab 4 screenshots/1.png>)

### Step 4 - Create the ECS cluster, as the developer role

part 1, assume the role & part 2, create the cluster

![alt text](<../../screenshots/Lab 4 screenshots/2.png>)

 part 3, restore your normal identity & Verify

![alt text](<../../screenshots/Lab 4 screenshots/3.png>)

### Step 5 - Create the log group the tasks will write to

![alt text](<../../screenshots/Lab 4 screenshots/4.png>)

### Step 6 - Create the task execution role

Verified that i have created the trust policy, the role, the permissions it needs, written as least privilege.

![alt text](<../../screenshots/Lab 4 screenshots/5.png>)

### Step 7 - Create the task role, and reuse Lab 1's policy on it
![alt text](<../../screenshots/Lab 4 screenshots/6.png>)

### Step 8 - Create the enrolment security group, sourced from the web tier's group

verify 

![alt text](<../../screenshots/Lab 4 screenshots/7.png>)


### Step 9 - Write and register the task definition
Verify

![alt text](<../../screenshots/Lab 4 screenshots/8.png>)

### Step 10 - Create the service in Lab 2's private subnets

![alt text](<../../screenshots/Lab 4 screenshots/9.png>)

usms-enrolment-svc is ACTIVE on Fargate with 2 desired and 2 running tasks across both private subnets, using usms-enrolment-sg with public IP disabled.

### Step 11 - Read the service back, and learn the four numbers

![alt text](<../../screenshots/Lab 4 screenshots/10.png>)

Your Turn 
![alt text](<../../screenshots/Lab 4 screenshots/11.png>)

### Step 12 - Write configs/lab-04.env
verify 

![alt text](<../../screenshots/Lab 4 screenshots/12.png>)










