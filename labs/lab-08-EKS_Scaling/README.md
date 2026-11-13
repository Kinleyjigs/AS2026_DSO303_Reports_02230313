# Lab 08 - EKS Scaling and Service Exposure

## 1. Objectives
- Scale a Deployment by hand, by manifest and with an `autoscaling/v2` HorizontalPodAutoscaler, and compare the HPA with Lab 06's Application Auto Scaling.
- Try to change the managed node group's scaling from the AWS side, and explain why that is a separate control loop.
- Use requests, QoS classes, a `nodeSelector` and PodDisruptionBudgets, and say what each one does and does not protect.
- Climb the exposure ladder: `port-forward`, `NodePort`, `LoadBalancer`, `Ingress`, and compare Ingress with Lab 05's ALB.
- Prove the scaling and exposure configuration survives a Floci restart, and save it to `configs/lab-08.env`.

## 2. Prerequisites
- Lab 07 complete: `configs/lab-07.env` populated and `verify-lab-07.sh` at PASS=30 FAIL=0 (support Path A).
- `usms-enrolment` declares a CPU request of `50m` (the HPA's denominator) and the cluster carries the `_lb_ports_=8081,8082` tag.
- Labs 05 and 06 complete, because Steps 15 to 17 compare against them.
- Tools: kubectl and AWS CLI v2. The env files `course.env`, `lab-01.env`, `lab-02.env`, `lab-04.env` and `lab-07.env` sourced, and `KUBECONFIG` pointing at `outputs/lab-07-kubeconfig.yaml`.

## 7. Step-by-Step Implementation

### Step 1 - Start the environment, and check the two things Lab 07 had to leave behind
![alt text](<../../screenshots/Lab 8 screenshots/1.png>)

*Figure 1: Prerequisite checks. usms-enrolment requests cpu 50m, the cluster carries `_lb_ports_=8081,8082`, verify-lab-07.sh reports PASS=30 FAIL=0, and every Service is still ClusterIP.*

### Step 2 - Read your own baseline before you change anything
A baseline was saved to `outputs/lab-08-baseline.txt`: usms-enrolment 2/2, usms-results 2/2, usms-gateway 1/1, every Service ClusterIP with no external address, and one node (`i-acfd2de022a9365b8.ec2.internal`, 8 CPU) Ready. Floci runs a single k3s node, so every "per node" check later in the lab has only one node.

### Step 3 - The four dimensions of scaling
#### Your Turn
*usms-enrolment needs to handle ten times its current traffic. Walk through the four dimensions and say which you would use, in which order, and what you would check between each.*

First I would scale horizontally at the workload level (dimension 1) by raising the HPA's `maxReplicas`, and check that the new pods become Ready and not Pending. If pods sit Pending, I would add nodes (dimension 3) by raising the node group's `desiredSize` and `maxSize`, and check that the nodes join as Ready and the Pending pods schedule. Only if each pod is hitting its CPU limit would I make the pods bigger (dimension 2), checking `kubectl top pods` first, because changing requests restarts the pods and changes the HPA's denominator. Bigger nodes (dimension 4) cannot be changed in place, so I would only do that last, by creating a new node group and draining the old one.

### Step 4 - Scale by hand, and watch what moves
![alt text](<../../screenshots/Lab 8 screenshots/2.png>)

*Figure 2: `kubectl scale --replicas=5` brings usms-enrolment to 5/5 with five endpoints, and 40 requests through the gateway are spread across all five pods (10, 9, 8, 7 and 6 requests).*

`kubectl scale` only wrote `spec.replicas`, so the same ReplicaSet was scaled and no rollout happened. In the watcher, each new pod went Pending, then ContainerCreating, then Running 0/1, and only became 1/1 (and joined the endpoints) about 6 seconds later when the readiness probe passed. When scaling back to 2, pods were removed from the endpoints first and then terminated.

### Step 5 - Scale declaratively, and meet configuration drift
![alt text](<../../screenshots/Lab 8 screenshots/3.png>)

*Figure 3: Drift. The cluster was scaled to 6 while the manifest still says `replicas: 2` (line 35); applying the unchanged file silently put the Deployment back to 2.*

`kubectl diff` was then used before changing `replicas` to 3 and back to 2. It exits with code 1 when there is a difference, which is a feature, so `|| true` is needed in a `set -e` shell. usms-enrolment ended at 2/2 with no `.bak` files left.

### Step 6 - Requests, limits and QoS classes
![alt text](<../../screenshots/Lab 8 screenshots/4.png>)

*Figure 4: All Lab 07 pods are Burstable (request 50m, limit 200m). usms-gateway was made Guaranteed by setting requests equal to limits and then put back to Burstable; a new pod was created each time.*

#### Your Turn
The gateway pod was **replaced**, not adjusted, because requests and limits are part of the pod template and changing them is dimension 2 (vertical scaling), which needs a new pod. This is why the VerticalPodAutoscaler is used much less than the HPA. I would want `Guaranteed` for a critical pod that must be evicted last under memory pressure, such as a database or the only replica of a gateway.

The HPA target is a percentage of the **request**, not of the node or the limit: 50% of a 50m request means 25m average per pod.

### Step 7 - The metrics pipeline
![alt text](<../../screenshots/Lab 8 screenshots/5.png>)

*Figure 5: metrics-server is installed and the `v1beta1.metrics.k8s.io` APIService is True, so the metrics API is AVAILABLE. Idle pods use about 1m CPU (2% of the request) and the node uses 173m (8%).*

k3s ships metrics-server by default, so nothing had to be installed and `--kubelet-insecure-tls` was not needed.

### Step 8 - Create the HorizontalPodAutoscaler
![alt text](<../../screenshots/Lab 8 screenshots/6.png>)

*Figure 6: usms-enrolment-hpa (autoscaling/v2, min 2, max 8, CPU 50%) first shows `<unknown>`, then `cpu: 2%/50%`. ScalingActive is True (ValidMetricFound) and ScalingLimited is False (DesiredWithinRange).*

The `behavior` block encodes "instant out, slow in": scale-up has no stabilisation window and allows +100% or +2 pods every 15s (`selectPolicy: Max`), while scale-down waits 300 seconds and removes at most 1 pod per minute (`selectPolicy: Min`). This matches Lab 06's `ScaleInCooldown: 300`.

### Step 9 - Generate load and watch it respond
![alt text](<../../screenshots/Lab 8 screenshots/7.png>)

*Figure 7: The usms-loadgen Deployment (busybox looping wget against the gateway's /enrolment/) applied and rolled out with 3 replicas.*

![alt text](<../../screenshots/Lab 8 screenshots/8.png>)

*Figure 8: HPA events. "New size: 3; reason: cpu resource utilization (percentage of request) above target", and about five minutes later "New size: 2; reason: All metrics below target". The HPA is back at 2%/50% with 2 replicas.*

With 3 load generators, CPU went 2% → 14% → 53%, but the HPA did not scale. 53/50 = 1.06 is inside the HPA's default 10% tolerance, so no change was made. I scaled usms-loadgen to 8; the enrolment pods reached 34m and 30m (about 64%), and the HPA scaled 2 → 3: ceil(2 × 64 / 50) = ceil(2.56) = 3. The single gateway pod was the bottleneck, which is why the load did not climb higher. After usms-loadgen was scaled to 0, CPU fell straight away but the replicas stayed at 3 for the 300-second stabilisation window, then went back to 2 (about 5m16s later).

### Step 10 - Scale the data plane from the AWS side
![alt text](<../../screenshots/Lab 8 screenshots/9.png>)

*Figure 9: describe-nodegroup shows usms-eks-nodes ACTIVE at min 2 / max 4 / desired 2, t3.small, labels workload=usms and tier=app. `update-nodegroup-config` fails with UnknownOperationException, and the node shows no workload label.*

`update-nodegroup-config` failed with `UnknownOperationException: Unknown operation: POST /clusters/usms-eks-cluster/node-groups/usms-eks-nodes/update-config`. This is the known Floci 2.0.1 issue, so the node group stayed at 2/4/2. On real AWS this would return an asynchronous Update object and the Auto Scaling group would launch a third EC2 instance. Even then, raising `replicas` and raising `desiredSize` are two separate control loops on two different APIs, and nothing connects them unless a Cluster Autoscaler or Karpenter is installed.

### Step 11 - Cluster Autoscaler and Karpenter, and a nodeSelector
- **Cluster Autoscaler** watches Pending pods and raises the desired capacity of a node group (Auto Scaling group) that I defined in advance.
- **Karpenter** watches the same Pending pods but launches EC2 instances directly, choosing an instance type that fits them.

Neither is installed here, because both need IRSA and a real Auto Scaling group.

![alt text](<../../screenshots/Lab 8 screenshots/10.png>)

*Figure 10: With `nodeSelector: workload=nonexistent`, the new pod stays Pending with FailedScheduling ("didn't match Pod's node affinity/selector"), while the two old pods keep Running because of `maxUnavailable: 0`.*

The node group's labels did not reach the node on Floci, so the node was labelled `workload=usms tier=app` by hand. The selector was then set back to `workload=usms`, the pods rolled out, and `manifests/lab-07/20-enrolment.yaml` was updated with the nodeSelector so the repository matches the cluster. The PDF's Python insert did not match my file (`topologySpreadConstraints` comes before `containers`), so I inserted it before `topologySpreadConstraints` instead.

### Step 12 - A PodDisruptionBudget, and what it does not protect against
![alt text](<../../screenshots/Lab 8 screenshots/11.png>)

*Figure 11: usms-gateway-pdb (minAvailable 1) allows 0 disruptions and usms-enrolment-pdb (maxUnavailable 1) allows 1. The eviction API is refused with TooManyRequests, but a plain `kubectl delete pod` goes straight through and a replacement pod starts.*

Lab 07 already had a `usms-enrolment-pdb` with `minAvailable: 1`. This lab replaced it with `maxUnavailable: 1`, which scales with the HPA's replica count. A PDB only limits **voluntary** evictions (drain, autoscaler scale-in); `kubectl delete` and involuntary failures ignore it. A real drain was not run, because with one node and a single-replica gateway it would hang on the gateway PDB.

### Step 13 - Rung one: ClusterIP and port-forward
![alt text](<../../screenshots/Lab 8 screenshots/12.png>)

*Figure 12: The gateway's ClusterIP 10.100.48.162 is not routable from the Mac. `kubectl port-forward svc/usms-gateway 18080:80` opens a tunnel through the API server.*

![alt text](<../../screenshots/Lab 8 screenshots/13.png>)

*Figure 13: Through the tunnel, `/`, `/enrolment/` and `/results/` return JSON from usms-gateway, usms-enrolment and usms-results.*

port-forward is for debugging only: it is a single tunnel to a single pod (no load balancing), and it only exists while the command runs on my machine.

### Step 14 - Rung two: NodePort
![alt text](<../../screenshots/Lab 8 screenshots/14.png>)

*Figure 14: usms-results-np is created as a second Service on the same pods, type NodePort `80:30080/TCP`. Calling the node IP 172.17.0.2:30080 from a pod inside the cluster returns usms-results JSON.*

`curl http://localhost:30080/` from the Mac got no answer, because the node container does not publish port 30080 (Floci limitation). Running `kubectl port-forward svc/usms-results-np 30080:80` returned JSON, but that only proves the Service works, not that the NodePort is reachable from outside.

### Step 15 - Rung three: LoadBalancer
![alt text](<../../screenshots/Lab 8 screenshots/15.png>)

*Figure 15: usms-gateway re-applied as type LoadBalancer. EXTERNAL-IP goes from `<pending>` to 172.17.0.2, and wget to that IP from inside the cluster reaches the gateway. Host ports 8081 and 8082 returned nothing. One line shows the ladder: `type=LoadBalancer clusterIP=10.100.48.162 nodePort=31999 external=172.17.0.2`.*

The external address came from k3s's built-in service load balancer (the node's own IP). The `_lb_ports_` ports were not published to the host on this build. A LoadBalancer Service still has a nodePort and a clusterIP, so each rung keeps the one below it. On real EKS, the three annotations would create an internet-facing NLB in the public subnets with `nlb-target-type: ip`, the same target type as Lab 05's target group, so the load balancer reaches pod IPs directly.

### Step 16 - Rung four: Ingress
![alt text](<../../screenshots/Lab 8 screenshots/16.png>)

*Figure 16: There is no IngressClass and no ingress controller pod. usms-portal-ingress is stored with three prefix paths that resolve to live endpoints, but it has CLASS `<none>` and no ADDRESS.*

Without a controller, the Ingress is a valid stored object that nothing acts on (Floci limitation). Kubernetes uses the **longest matching prefix**, so `/enrolment/x` goes to usms-enrolment even though `/` also matches; Lab 05's ALB used numeric rule priority instead.

#### Your Turn
*Which four `aws elbv2` commands from Lab 05 would the AWS Load Balancer Controller have run on your behalf, and in what order?*
1. `create-load-balancer`: an internet-facing ALB in the public subnets (`scheme`, `tags` annotations).
2. `create-target-group --target-type ip`: one per backend Service (`target-type`, `healthcheck-path` annotations).
3. `create-listener`: HTTP on port 80 (`listen-ports` annotation).
4. `create-rule`: one per path (`/enrolment`, `/results`), with `/` as the default action (`spec.rules[].http.paths[]`).

### Step 17 - Practical 2 / Practical 4 comparison, with both systems running
![alt text](<../../screenshots/Lab 8 screenshots/17.png>)

*Figure 17: Both stacks running at once. ECS usms-enrolment-svc at 2/2 behind usms-enrolment-tg, scalable target min 2 max 10 with four scaling policies; EKS with the HPA at 2%/50%, the LoadBalancer and NodePort Services, the Ingress and both PDBs.*

#### Scaling
| Question | ECS + Application Auto Scaling | Kubernetes + HPA |
| --- | --- | --- |
| What integer is written? | The service's `desiredCount` | The Deployment's `spec.replicas` |
| Who writes it? | Application Auto Scaling | The HPA controller |
| Where does that thing run? | In AWS, outside anything I own | In the cluster's controller manager |
| Where does the metric come from? | CloudWatch (ECSServiceAverageCPUUtilization) | metrics-server via `metrics.k8s.io` |
| What does "50% CPU" mean? | 50% of the task's reserved CPU | 50% of the container's CPU request (25m of 50m) |
| How is scale-in slowed down? | `ScaleInCooldown: 300` | `scaleDown.stabilizationWindowSeconds: 300` and 1 pod/min |
| No capacity for the new task/pod? | Fargate always finds capacity | The pod stays Pending until a node is added |
| What creates the alarms? | Two CloudWatch alarms created automatically | No alarms; the controller polls every 15s |

#### Exposure
| Question | ECS + ALB (Lab 05) | Kubernetes + Ingress (Step 16) |
| --- | --- | --- |
| How many AWS objects did I create by hand? | ALB, target group, listener, rule, security group | None; one Ingress object (the controller would create them) |
| Target type, and why? | `ip`, because each Fargate task has its own VPC address | `ip`, because each pod has its own VPC address |
| How are targets registered? | ECS registers and deregisters tasks | The controller watches the Service's Endpoints |
| Competing rules disambiguated by | Numeric rule priority | Longest matching prefix |
| Moving to another cloud | Rebuild everything with that cloud's API | Change the ingress class and annotations; the rules stay |
| Cost of exposing ten services | One ALB with ten rules (or ten ALBs if done per service) | One Ingress = one ALB; ten LoadBalancer Services = ten NLBs |

If the AWS control plane has a bad afternoon, ECS scaling stops completely because Application Auto Scaling and CloudWatch alarms are AWS services, and I can only see what the console and CLI show me. The HPA keeps running inside the cluster as long as the Kubernetes API server is up, and I can still debug it with `kubectl describe hpa` and its events. For USMS (a small team, one region, quiet for eight months and busy for two), I would choose ECS on Fargate, because there are no nodes to patch and it never runs out of capacity at peak. The strongest argument against that choice is portability and control: Kubernetes manifests, the HPA's `behavior` block and one Ingress for many services would move to another cloud almost unchanged.

### Step 18 - Prove that scaling and exposure configuration survive a restart
![alt text](<../../screenshots/Lab 8 screenshots/18.png>)

*Figure 18: After a Floci stop and start, the HPA (2/8/50), both PDBs, the Services (usms-results-np still pinned to 30080, usms-gateway LoadBalancer on 31999), the Ingress paths and the node group (2 4 2) all read back identical: PERSISTENCE PROVEN.*

Even the auto-allocated gateway nodePort (31999) did not change this time. The node group shows 2/4/2 because the Step 10 update was never applied.

### Step 19 - Write configs/lab-08.env
`configs/lab-08.env` was generated from live values with **19** exports: `hpa: 2..8 at 50% cpu, scale-in window 300s`, `nodeport: 30080`, `gateway: LoadBalancer`. `USMS_INGRESS_CLASS` is empty because no ingress controller is running, and the node group values are 2/4/2 because of the Step 10 failure.

The first attempt produced empty HPA values. Long pasted lines were cut by the terminal, and storing a command in a variable does not work in zsh, so the four HPA values were looked up again and filled in. The PDF's `grep 'export .*=$\|None'` check also gave a false "all values populated" on macOS, because BSD grep does not support `\|`; `grep -E 'export .*=$|None'` works.

### Step 20 - Commit
All Lab 08 manifests, the updated `manifests/lab-07/20-enrolment.yaml`, `configs/lab-08.env`, `verify-lab-08.sh`, `hpa-watch.sh`, `lab-08-cleanup.sh`, the notes and the screenshots were committed. `git check-ignore -v outputs/lab-08-baseline.txt` named the rule `.gitignore:8:outputs/*`, and only `outputs/.gitkeep` is tracked under `outputs/`.

## 8. Verification
![alt text](<../../screenshots/Lab 8 screenshots/19.png>)

*Figure 19: verify-lab-08.sh reports PASS=33 FAIL=1. The only failure is "node group maxSize was raised to 6", caused by the Floci 2.0.1 update-nodegroup-config issue.*

The script's original "no secret is tracked by git" check failed because it matched `outputs/.gitkeep`, which the lab itself expects to be tracked. I changed it to ignore `.gitkeep`, so it still fails if any real output file is committed. The cleanup script `scripts/cleanup/lab-08-cleanup.sh` was written and passed `bash -n`, but was **not run**. In Section 15, `usms-loadgen` and any leftover debug pods were deleted and no node was left cordoned.

## Floci vs Real AWS (what I saw)
| Feature | Real AWS | On Floci | Status |
| --- | --- | --- | --- |
| HPA autoscaling/v2 with behavior | Standard | Worked; scaled 2 → 3 → 2 | Observed |
| metrics-server / `kubectl top` | EKS add-on | Shipped with k3s and AVAILABLE | Observed |
| `update-nodegroup-config` | ASG changes, a node joins | UnknownOperationException; stays 2/4/2 | Floci limitation |
| Node group labels on nodes | Applied automatically | Not applied; labelled by hand | Floci limitation |
| PDB and eviction API | Standard | Eviction refused, delete allowed | Observed |
| NodePort from the host | Reachable through the security group | Not published (port-forward fallback) | Floci limitation |
| type: LoadBalancer | An NLB with pod IP targets | k3s gave the node IP 172.17.0.2; 8081/8082 not published | Partly observed |
| Ingress | AWS Load Balancer Controller creates an ALB | No controller; stored but no address | Conceptual |
| Cluster Autoscaler / Karpenter | Adds nodes for Pending pods | Not installed (needs IRSA and an ASG) | Conceptual |

## Analysis
In this lab, I learned that scaling in Kubernetes is always one integer, and what changes is who writes it: me with `kubectl scale`, Git through the manifest, or the HPA. I saw configuration drift happen when an unchanged manifest silently undid my manual scaling, and learned to use `kubectl diff` before every apply. I learned that the HPA's 50% target is a percentage of the CPU request, not of the node, and that it has a 10% tolerance, which is why 53% did not cause scaling but 64% did. I also saw that the HPA and the node group are two separate control loops, and that a PDB only protects against evictions, not a plain delete. On the exposure side, I climbed from ClusterIP and port-forward to NodePort, LoadBalancer and Ingress, and saw that each rung keeps the one below it. Floci could not resize the node group, publish NodePorts or LoadBalancer ports to my Mac, or run an ingress controller, so I recorded those results honestly and explained what real EKS would do instead.
