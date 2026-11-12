# Lab 07 - Deploying a Microservices Application on Amazon EKS

## 1. Objectives

## 2. Prerequisites

## 5. Architecture

## 7. Step-by-Step Implementation

### Step 1 - Start the environment and confirm the ground you are standing on
![alt text](<../../screenshots/Lab 7 screenshots/1.png>)
Figure 1: Step 1 checks. The Lab 02 and Lab 04 verify scripts were run, and all four Lab 02 subnet IDs (public-a/b, private-a/b) were confirmed present.

### Step 2 - Probe what your build actually supports, and record the answer

![alt text](<../../screenshots/Lab 7 screenshots/2.png>)

Figure 2: EKS support probe. Floci is running, the EKS API answers and kubectl is installed, so the verdict is Path A, which is recorded in the lab notes.

### Step 3: control plane vs data plane (no commands)
#### Your Turn 
```
        CONTROL PLANE                    |            DATA PLANE
        AWS runs it. You cannot log in.  |            You run it. You can log in.
   ----------------------------------------------------------------------------
        kube-apiserver                   |   EC2 instances in YOUR account
        etcd (the cluster's database)    |   the kubelet on each of them
        kube-scheduler                   |   the container runtime
        kube-controller-manager          |   your pods
        cloud-controller-manager         |   the CNI plugin that gives pods VPC addresses
   ----------------------------------------------------------------------------
        billed per cluster per hour      |   billed per instance, as ordinary EC2
        patched by AWS                   |   patched by YOU
        one IAM role: cluster role       |   one IAM role: node role
```

*a colleague says "EKS is just ECS with different names". Name one thing in the table above that makes that statement false, and one thing that makes it nearly true.*

**Why it is false:**
- EKS is different from ECS because in EKS, I have to manage the data plane, including the EC2 worker nodes, kubelet and CNI plugin. I am also responsible for patching and maintaining them, while AWS manages the control plane. In ECS with Fargate, AWS manages the infrastructure, so I do not need to manage worker nodes.

**Why it is nearly true:**
- EKS and ECS are nearly similar because both have an AWS-managed control plane that decides where containers should run. Both also allow me to define the desired number of running containers and maintain them. EKS uses Kubernetes Deployment and Service, while ECS uses Task Definition and Service.

### Step 4 - Write the two trust policies

![alt text](<../../screenshots/Lab 7 screenshots/3.png>)

Figure 3: Trust policies for the two EKS roles. Both files are valid JSON; the cluster role trusts eks.amazonaws.com and the node role trusts ec2.amazonaws.com.


### Step 5 - Write the two permissions policies
![alt text](<../../screenshots/Lab 7 screenshots/4.png>)

 Figure 4: EKS permissions policies. The cluster policy has 3 statements and the node policy has 5, each ending with a region Deny.

### Step 6 - Create the cluster role and the cluster security group
![alt text](<../../screenshots/Lab 7 screenshots/5.png>)

Figure 5: The usms-eks-cluster-role is created and USMSEKSClusterPolicy is attached. The usms-eks-cluster-sg group is created in usms-vpc and allows TCP 443 from 10.0.0.0/16.

![alt text](<../../screenshots/Lab 7 screenshots/6.png>)
Figure 6: Cluster role check. The role carries only USMSEKSClusterPolicy and trusts eks.amazonaws.com, and its security group sits in usms-vpc with port 443 open.

### Step 7 - Create the node role, and attach Lab 1's policy to it
![alt text](<../../screenshots/Lab 7 screenshots/7.png>)

Figure 7: usms-eks-node-role is created, trusting ec2.amazonaws.com, with USMSEKSNodePolicy attached. Lab 1's USMSStudentDataReadWrite is attached unchanged and now has three holders: usms-ec2-app-role, usms-ecs-task-role and usms-eks-node-role.


Step 8 - Create the cluster

















