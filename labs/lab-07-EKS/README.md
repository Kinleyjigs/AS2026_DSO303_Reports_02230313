# Lab 07 - Deploying a Microservices Application on Amazon EKS

## 1. Objectives
- Create an EKS cluster and a managed node group inside Lab 02's VPC, each with its own IAM role.
- Point kubectl at the cluster and deploy three microservices (usms-gateway, usms-enrolment, usms-results) from YAML manifests.
- Prove the services find each other by DNS name, then do a rolling update, a rollback and three deliberate failure diagnoses.
- Use a ConfigMap and a Secret, and show what a Secret does not protect.
- Prove the cluster survives a Floci restart and save its identifiers to `configs/lab-07.env` for Lab 08.

## 2. Prerequisites
- Labs 01 to 04 complete. `verify-lab-02.sh` reports FAIL=0, and all four Lab 02 subnets (public-a/b, private-a/b) exist in two Availability Zones.
- Floci running under Docker Compose in hybrid storage mode, with about 2 GB of free RAM for the Kubernetes node container.
- Tools: Docker Desktop, AWS CLI v2, python3 and **kubectl** (the one new tool). k3d was not installed and was not needed (Path A).
- The env files `course.env` and `lab-01.env` to `lab-04.env` sourced in the terminal.

## 7. Step-by-Step Implementation

### Step 1 - Start the environment and confirm the ground you are standing on
![alt text](<../../screenshots/Lab 7 screenshots/1.png>)

*Figure 1: Step 1 checks. The Lab 02 and Lab 04 verify scripts were run, and all four Lab 02 subnet IDs (public-a/b, private-a/b) were confirmed present.*

### Step 2 - Probe what your build actually supports, and record the answer
![alt text](<../../screenshots/Lab 7 screenshots/2.png>)

*Figure 2: EKS support probe. Floci is running, the EKS API answers and kubectl is installed, so the verdict is Path A, which is recorded in the lab notes.*

### Step 3 - Control plane vs data plane
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

*A colleague says "EKS is just ECS with different names". Name one thing in the table above that makes that statement false, and one thing that makes it nearly true.*

**Why it is false:**
- EKS is different from ECS because in EKS, I have to manage the data plane, including the EC2 worker nodes, kubelet and CNI plugin. I am also responsible for patching and maintaining them, while AWS manages the control plane. In ECS with Fargate, AWS manages the infrastructure, so I do not need to manage worker nodes.

**Why it is nearly true:**
- EKS and ECS are nearly similar because both have an AWS-managed control plane that decides where containers should run. Both also allow me to define the desired number of running containers and maintain them. EKS uses Kubernetes Deployment and Service, while ECS uses Task Definition and Service.

### Step 4 - Write the two trust policies
![alt text](<../../screenshots/Lab 7 screenshots/3.png>)

*Figure 3: Trust policies for the two EKS roles. Both files are valid JSON; the cluster role trusts eks.amazonaws.com and the node role trusts ec2.amazonaws.com.*

### Step 5 - Write the two permissions policies
![alt text](<../../screenshots/Lab 7 screenshots/4.png>)

*Figure 4: EKS permissions policies. The cluster policy has 3 statements and the node policy has 5, each ending with a region Deny.*

### Step 6 - Create the cluster role and the cluster security group
![alt text](<../../screenshots/Lab 7 screenshots/5.png>)

*Figure 5: usms-eks-cluster-role is created and USMSEKSClusterPolicy is attached. usms-eks-cluster-sg is created in usms-vpc and allows TCP 443 from 10.0.0.0/16.*

![alt text](<../../screenshots/Lab 7 screenshots/6.png>)

*Figure 6: Cluster role check. The role carries only USMSEKSClusterPolicy and trusts eks.amazonaws.com, and its security group sits in usms-vpc with port 443 open.*

> **Issue:** On the first try I also ran the "Real AWS, do not run" block, which attached AmazonEKSClusterPolicy. I deleted the role, policy and security group and recreated them cleanly.

### Step 7 - Create the node role, and attach Lab 1's policy to it
![alt text](<../../screenshots/Lab 7 screenshots/7.png>)

*Figure 7: usms-eks-node-role is created, trusting ec2.amazonaws.com, with USMSEKSNodePolicy attached. Lab 1's USMSStudentDataReadWrite is attached unchanged and now has three holders: usms-ec2-app-role, usms-ecs-task-role and usms-eks-node-role.*

### Step 8 - Create the cluster
![alt text](<../../screenshots/Lab 7 screenshots/8.png>)

*Figure 8: usms-eks-cluster (Kubernetes 1.30) is created as usms-developer-role from the request body and returns status CREATING, then my normal identity is restored.*

> **Issue:** The first create-cluster returned **FAILED**. The Floci logs showed that the first k3s image download took about 57 seconds, the AWS CLI retried the request, and two k3s containers removed each other ("No such container"). I deleted the cluster and created it again with `AWS_MAX_ATTEMPTS=1` and `--cli-read-timeout 300`, which worked.

### Step 9 - Wait for the cluster, and read what it tells you
![alt text](<../../screenshots/Lab 7 screenshots/9.png>)

*Figure 9: usms-eks-cluster is ACTIVE on Kubernetes 1.30 in usms-vpc across all four subnets. Its endpoint is https://localhost:6500 and it carries the _lb_ports_=8081,8082 tag for Lab 08.*

#### Your Turn
![alt text](<../../screenshots/Lab 7 screenshots/10.png>)

*Figure 10: One --query prints Kubernetes 1.30 next to the cluster's OIDC issuer URL.*

The OIDC issuer is the cluster's identity-provider URL. IAM trusts it so a pod's ServiceAccount token can be exchanged for an IAM role (IRSA), giving each pod its own permissions instead of sharing the node role. This build returned a real URL rather than `None`.

### Step 10 - Create the managed node group
![alt text](<../../screenshots/Lab 7 screenshots/11.png>)

*Figure 11: usms-eks-nodes is ACTIVE in the two private subnets with usms-eks-node-role, scaling min 2 / max 4 / desired 2, and labels workload=usms and tier=app.*

`t3.small` is recorded but not provisioned on Floci; the cluster actually ran as one k3s node.

### Step 11 - Point kubectl at the cluster
![alt text](<../../screenshots/Lab 7 screenshots/12.png>)

*Figure 12: kubectl connected to the cluster. The control plane answers at https://localhost:6500, one node is Ready on v1.30.10+k3s1, and the admin credential can create deployments.*

> **Issue:** `aws eks update-kubeconfig` worked, but kubectl was refused with "the server has asked for the client to provide credentials", because Floci's k3s does not accept `aws eks get-token`. k3d was not installed, so I used the certificate-based fallback: I read `/etc/rancher/k3s/k3s.yaml` from the k3s container with `docker exec`, pointed it at `https://localhost:6500`, and saved it to `outputs/lab-07-kubeconfig.yaml` (chmod 600, git-ignored).

### Step 12 - Create the namespace and make it the default
![alt text](<../../screenshots/Lab 7 screenshots/13.png>)

*Figure 13: Namespace usms is created from 00-namespace.yaml with labels project, tier and lab. It is set as the default namespace and is empty for now.*

### Step 13 - Deploy the first microservice: usms-enrolment
![alt text](<../../screenshots/Lab 7 screenshots/14.png>)

*Figure 14: usms-enrolment is rolled out. The Deployment has 2/2 pods Running and its ClusterIP Service sends traffic to both pod endpoints.*

![alt text](<../../screenshots/Lab 7 screenshots/15.png>)

*Figure 15: A temporary busybox pod reaches usms-enrolment by its DNS name. The JSON shows which pod answered plus values from the ConfigMap.*

> **Issue:** Pods showed `ErrImagePull` / `ImagePullBackOff` because the k3s node could not resolve Docker Hub's CDN (`lookup production.cloudfront.docker.com: no such host`). I pulled `nginx:1.27-alpine` and `busybox:1.36` on my Mac and loaded them into the node with `docker save | docker exec -i <k3s container> ctr images import -`. This is the PDF's Troubleshooting fix, done without k3d.

### Step 14 - Deploy the second microservice: usms-results
![alt text](<../../screenshots/Lab 7 screenshots/16.png>)

*Figure 16: usms-results is deployed next to usms-enrolment. Both are 2/2 with two endpoints each; enrolment uses maxUnavailable 0 and results uses the default 25%.*

### Step 15 - Deploy the gateway, and meet cluster DNS
![alt text](<../../screenshots/Lab 7 screenshots/17.png>)

*Figure 17: All three microservices are running in namespace usms (2 enrolment, 2 results, 1 gateway), and the gateway log shows nginx started cleanly.*

### Step 16 - Prove service discovery from inside the cluster
![alt text](<../../screenshots/Lab 7 screenshots/18.png>)

*Figure 18: From inside a pod, CoreDNS resolves usms-enrolment and usms-results to their stable ClusterIP addresses, not pod IPs.*

![alt text](<../../screenshots/Lab 7 screenshots/19.png>)

*Figure 19: Through the gateway, the root answers itself, and /enrolment/ and /results/ are proxied by DNS name to the matching backend.*

![alt text](<../../screenshots/Lab 7 screenshots/20.png>)

*Figure 20: Twelve requests through the gateway were answered by both enrolment pods (5 and 7), because kube-proxy spreads traffic behind one ClusterIP.*

#### Your Turn
![alt text](<../../screenshots/Lab 7 screenshots/21.png>)

*Figure 21: After an enrolment pod was deleted, a replacement (4rxt6) appeared within 2 seconds. All 12 requests through the unchanged gateway still succeeded, served by the surviving pod while the new one became ready.*

The replacement pod was created by the **ReplicaSet**, not by the Deployment and not by me. It saw 1 of 2 desired pods and created another.

### Step 17 - ConfigMaps and Secrets
![alt text](<../../screenshots/Lab 7 screenshots/22.png>)

*Figure 22: A Secret is not encrypted. The stored value is only base64, and one `base64 -d` recovers the plaintext token with no key.*

![alt text](<../../screenshots/Lab 7 screenshots/23.png>)

*Figure 23: The enrolment pods now receive 4 APP_* values from the ConfigMap and 2 ENROLMENT_* values from the Secret. Inside the container the secret is plain text.*

`manifests/lab-07/50-secret.yaml` holds dummy values and is committed only as the lab asks. In a real repo it would go in `outputs/` or a secrets manager, because base64 in Git history is plaintext forever.

### Step 18 - Roll out a change, then roll it back
![alt text](<../../screenshots/Lab 7 screenshots/24.png>)

*Figure 24: After the ConfigMap changed to 1.1.0 and the rollout restarted, the enrolment pods report version 1.1.0 from a new ReplicaSet.*

![alt text](<../../screenshots/Lab 7 screenshots/25.png>)

*Figure 25: rollout history lists the revisions, and rollout undo scales a previous ReplicaSet back up instead of rebuilding anything.*

`rollout undo` reverts the pod template, **not** the ConfigMap, so the ConfigMap was restored to 1.0.0 by hand.

#### Your Turn
![alt text](<../../screenshots/Lab 7 screenshots/26.png>)

*Figure 26: usms-results was updated to nginx:1.27 and rolled back to revision 1. Two revisions remain (2 and 3) and the image is back on nginx:1.27-alpine.*

Revision 1 became revision 3 when it was rolled back to. Because usms-results uses the default 25% strategy, it can drop to 1 ready pod during a roll, while usms-enrolment (`maxUnavailable: 0`) never drops below 2.

### Step 19 - Break a pod deliberately, and diagnose it
![alt text](<../../screenshots/Lab 7 screenshots/27.png>)

*Figure 27: Failure 1, a wrong image tag. The new pod is stuck in ImagePullBackOff while the two old usms-results pods keep serving.*

![alt text](<../../screenshots/Lab 7 screenshots/28.png>)

*Figure 28: Failure 2, unschedulable. A pod requesting 64 CPUs and 256 GiB stays Pending with FailedScheduling.*

![alt text](<../../screenshots/Lab 7 screenshots/29.png>)

*Figure 29: Failure 3, CrashLoopBackOff. The container exits with code 1, and `logs --previous` shows "fatal: no database configured".*

| Failure | What `get pods` shows | Where the answer was |
| --- | --- | --- |
| Wrong image tag | ImagePullBackOff | Events in `describe pod` |
| Requests too big | Pending | Events in `describe pod` (FailedScheduling) |
| App exits 1 | CrashLoopBackOff | `logs --previous` |

### Step 20 - ECS vs Kubernetes comparison
![alt text](<../../screenshots/Lab 7 screenshots/30.png>)

*Figure 30: ECS and EKS side by side. Lab 04's usms-enrolment-svc (2/2, task definition :3) and the three usms Deployments and ClusterIP Services on EKS.*

| Question | ECS answer | Kubernetes answer |
| --- | --- | --- |
| What holds the container spec? | Task definition (revisions) | Deployment pod template (YAML) |
| What keeps N copies alive? | ECS service scheduler (desiredCount) | ReplicaSet (replicas: 2) |
| What gives it a stable name? | ALB / service discovery name | ClusterIP Service + DNS name |
| How does another service find it? | ALB DNS name or Cloud Map | CoreDNS resolves the Service name; kube-proxy forwards |
| What does a rolling update create? | New deployment with a new task definition | New ReplicaSet (old one kept at 0) |
| Where does rollback state live? | Old task definition revisions | Old ReplicaSets (revisionHistoryLimit 5) |
| Which IAM role does the app use? | Task role (per task) | Node role (shared), unless IRSA |
| What changes to move cloud? | Almost everything | Manifests move; IAM, VPC, node groups do not |

For USMS I would choose **ECS on Fargate**. It is three small stateless services, and Fargate removes node patching, the second IAM role and the cluster cost. EKS makes sense only if USMS grows into many services that need Kubernetes portability.

### Step 21 - IRSA
![alt text](<../../screenshots/Lab 7 screenshots/31.png>)

*Figure 31: The cluster's OIDC issuer is registered in IAM as an OpenID Connect provider, and the usms-enrolment-sa ServiceAccount is created in namespace usms.*

| IRSA step | Done on this build? |
| --- | --- |
| 1. Cluster publishes an OIDC issuer | Yes |
| 2. Issuer registered in IAM as an OIDC provider | Yes |
| 3. Web-identity trust role | No (not enforced on Floci) |
| 4. ServiceAccount usms-enrolment-sa | Yes (not annotated yet) |
| 5. Webhook injects the token into pods | No (Floci: Pod Identity injection off, no TLS) |
| 6. SDK calls AssumeRoleWithWebIdentity | No (depends on 5) |

Until IRSA works, the node role gives USMSStudentDataReadWrite to **every** pod on the node.

### Step 22 - Prove that all of this survives a restart
![alt text](<../../screenshots/Lab 7 screenshots/32.png>)

*Figure 32: After a full Floci stop and start, the cluster and node group are re-derived from the API, all three Deployments are back at 2/1/2 ready, and the ConfigMaps survived.*

The diff lines are not data loss. The before-script records the nodegroup and Service lines and the after-script records namespace and ConfigMap lines, so those lines can never match. kubectl reconnected without rebuilding the kubeconfig.

### Step 23 - Write configs/lab-07.env
![alt text](<../../screenshots/Lab 7 screenshots/33.png>)

*Figure 33: configs/lab-07.env has 21 exports, all populated from the API (cluster ARN, endpoint, roles, policies, security group, _lb_ports_ 8081,8082), with no secrets.*

### Step 24 - Commit
All manifests, policies, templates, `configs/lab-07.env`, the probe script, notes and screenshots were committed. Nothing under `outputs/` (kubeconfig, before/after files) was committed.

## Floci vs Real AWS (what I saw)
| Feature | Real AWS | On Floci |
| --- | --- | --- |
| create-cluster | Managed control plane in 10-15 min | A k3s container in about 1 min (failed once due to a CLI retry) |
| Node group | Real t3.small EC2 instances | Recorded only; one k3s node runs the pods |
| kubectl login | `aws eks get-token` (IAM) | Refused; used the k3s certificate kubeconfig |
| IAM policies | Enforced | Stored, not enforced |
| IRSA | Works end to end | Issuer and provider only; no token injection |
| Pulling images | From the internet / ECR | Docker Hub DNS failed; images pre-loaded from the host |

## Analysis
In this lab, I learned that EKS has two parts: the AWS side, where I created the cluster, node group and two IAM roles, and the Kubernetes side, where I deployed three microservices using kubectl. I learned that services communicate using DNS names instead of IP addresses. When I deleted a pod, Kubernetes automatically created a new one, so the service continued working. I also learned how to update and roll back applications, check errors using pods, describe and logs, and that Kubernetes Secrets use Base64 encoding but are not fully secure. During the lab, I also faced problems with the cluster, kubectl login and image downloads on Floci. These problems helped me understand how to check logs and events to find and fix errors.

