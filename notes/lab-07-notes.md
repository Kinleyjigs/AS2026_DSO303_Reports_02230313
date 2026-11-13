## Step 3 - "EKS is just ECS with different names"
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

*Why it is false:*
- EKS is different from ECS because in EKS, I have to manage the data plane, including the EC2 worker nodes, kubelet and CNI plugin. I am also responsible for patching and maintaining them, while AWS manages the control plane. In ECS with Fargate, AWS manages the infrastructure, so I do not need to manage worker nodes.

*Why it is nearly true:*
- EKS and ECS are nearly similar because both have an AWS-managed control plane that decides where containers should run. Both also allow me to define the desired number of running containers and maintain them. EKS uses Kubernetes Deployment and Service, while ECS uses Task Definition and Service.

## Step 9 - Your turn: version and OIDC issuer
Output: 1.30	https://oidc.eks.us-east-1.amazonaws.com/id/B42686F67A5946C58B6A626F09BAC96F
The OIDC issuer is the cluster's identity-provider URL. IAM trusts it so a pod's Kubernetes ServiceAccount token can be exchanged for an IAM role (IRSA), giving each pod its own permissions instead of sharing the node role.
Note: this build returned a real issuer URL (not None), so it supports more than most Floci builds.

## Step 11 - kubeconfig
aws eks update-kubeconfig worked, but kubectl was refused ("server has asked for the client to provide credentials"): Floci's k3s does not accept aws eks get-token. k3d is not installed, so I used the certificate-based fallback by reading /etc/rancher/k3s/k3s.yaml from the k3s container with docker exec and pointing it at https://localhost:6500. Saved to outputs/lab-07-kubeconfig.yaml (chmod 600, git-ignored).
## Step 16 - Your turn
The replacement pod was created by the ReplicaSet (usms-enrolment-<hash>), not by the Deployment and not by me: the ReplicaSet saw 1 of 2 desired pods and created another to restore the count.
## Step 20 - ECS and Kubernetes, compared with both running
| Question | ECS answer | Kubernetes answer |
| --- | --- | --- |
| What holds the container spec? | Task definition (versioned revisions, e.g. usms-enrolment:N) | The Deployment's pod template (spec.template) in a YAML manifest |
| What keeps N copies alive? | The ECS service scheduler (desiredCount) | The ReplicaSet created by the Deployment (replicas: 2) |
| What gives it a stable name? | ALB target group / Service Connect or Cloud Map name | A ClusterIP Service with DNS name usms-enrolment.usms.svc.cluster.local |
| How does another service find it? | Through the ALB DNS name or service discovery | CoreDNS resolves the Service name to its ClusterIP; kube-proxy forwards to a ready pod |
| What does a rolling update create? | A new ECS deployment using a new task definition revision | A new ReplicaSet; the old one is scaled to 0 and kept |
| Where does rollback state live? | Old task definition revisions (redeploy the service with an older one) | Old ReplicaSets kept up to revisionHistoryLimit (5); kubectl rollout undo scales one back up |
| Which IAM role does the app code use? | The task role (usms-ecs-task-role), per task | The node role (usms-eks-node-role) shared by every pod on the node, unless IRSA/Pod Identity is used |
| What would I have to change to move to another cloud? | Almost everything: task definitions, services and IAM are ECS/AWS-specific | Manifests (Deployments, Services, ConfigMaps) move unchanged; IAM roles, VPC/subnets, node groups and load-balancer annotations must be redone |

For USMS I would choose ECS on Fargate: it is three small stateless services, and Fargate removes the node patching, the second IAM role and the cluster cost that EKS adds. I would only move to EKS if USMS grew to many services that needed Kubernetes portability or its ecosystem (HPA, Ingress, operators).
## Step 21 - IRSA on this build
1. OIDC issuer published: YES - describe-cluster returned https://oidc.eks.us-east-1.amazonaws.com/id/B42686F67A5946C58B6A626F09BAC96F
2. Registered in IAM as an OIDC provider: YES - arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/B42686F67A5946C58B6A626F09BAC96F
3. Web-identity trust role: not created - Floci stores but does not enforce trust conditions, and the issuer is not reachable by a real STS.
4. ServiceAccount usms-enrolment-sa: created (not yet annotated with a role ARN).
5. Mutating webhook injecting the token: NO - Floci logged "EKS Pod Identity injection is off ... Floci serves HTTP with floci.tls.enabled=false".
6. SDK calls sts:AssumeRoleWithWebIdentity from the pod: NO - depends on step 5.
Until IRSA works, the node role (usms-eks-node-role) gives USMSStudentDataReadWrite to every pod on the node, including a compromised one.
## Step 22 - persistence
After floci-down / floci-up, the cluster (ACTIVE 1.30), node group, namespace usms, all three Deployments (2/1/2 ready) and the ConfigMaps were all present. The diff is not a loss: the before-script records the nodegroup and Service lines, while the after-script records namespace and ConfigMap lines, so those lines can never match. kubectl reconnected without rebuilding the kubeconfig.
## Exercise 5 - what Lab 08 needs from configs/lab-07.env
- USMS_EKS_CLUSTER: every aws eks call in Lab 08 names the cluster.
- USMS_EKS_NODEGROUP: Lab 08 changes the node group's scaling config (the data-plane side of scaling).
- USMS_EKS_NAMESPACE: every kubectl command works inside namespace usms.
- USMS_EKS_LB_PORTS: Floci needs 8081,8082 to publish a LoadBalancer/Ingress; without it nothing outside the cluster is reachable.
- USMS_EKS_ENDPOINT: to confirm kubectl points at the right cluster after a restart (mine is https://localhost:6500).
- USMS_K8S_DEPLOY_ENROLMENT: the Deployment the HorizontalPodAutoscaler will target.
- USMS_K8S_DEPLOY_GATEWAY: the Deployment whose Service becomes NodePort, then LoadBalancer and Ingress.
- USMS_K8S_CPU_REQUEST: 50m, so I can check the HPA's percentage maths myself (my baseline was about 1m = 2%).
The rest (role ARNs, policy ARNs, security group, results/timetable names) are records of what exists, not inputs Lab 08 acts on.
