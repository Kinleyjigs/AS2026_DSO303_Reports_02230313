## Step 17 - Practical 2 and Practical 4, compared with both running

### Scaling

| Question | ECS + Application Auto Scaling | Kubernetes + HPA |
| --- | --- | --- |
| What integer is written? | | |
| Who writes it? | | |
| Where does that thing run? | | |
| Where does the metric come from? | | |
| What does "50% CPU" mean - 50% of what? | | |
| How is scale-in slowed down? | | |
| What happens if there is no capacity for the new instance/pod? | | |
| What creates the alarms, if anything? | | |

### Exposure

| Question | ECS + ALB (Lab 05) | Kubernetes + Ingress (Step 16) |
| --- | --- | --- |
| How many AWS objects did I create by hand? | | |
| What is the target type, and why? | | |
| How are targets registered and deregistered? | | |
| How are competing routing rules disambiguated? | | |
| What would I change to move this to another cloud? | | |
| What is the cost of exposing ten services? | | |

### Two paragraphs, in prose

1. If the AWS control plane has a bad afternoon, what happens to each of the two scaling arrangements, and which of them can I still debug?

2. For USMS specifically - one small team, one region, quiet for eight months and very busy for two - which would I choose, and what is the strongest argument AGAINST my own choice?

## Exercise 5 Part 3 - ECS or Kubernetes for USMS

**My choice: ECS on Fargate.**

Why:
- Small team, one region, busy only 2 months a year.
- Fargate always has room. On EKS the HPA added pods, but nothing added nodes (node group update failed), so pods can sit Pending.
- Lab 05 ALB worked fully. Here the Ingress got no address (no controller).
- No IRSA here, so S3 access had to come from the node role, shared by every pod. ECS task roles are per task.

Strongest argument against:
- Kubernetes gives more control (HPA behavior, PDBs) and one Ingress for many services, and moves to another cloud easily.

## Section 14 - Review Questions
## 1. Does HPA 50% mean the node is using 50% CPU?

- **No.** It means the pod is using 50% of its requested CPU, not the node's CPU.
- Example: If a pod requests 50m CPU, 50% means 25m CPU.
- If we reduce the CPU request to 25m, the same workload looks like 100% CPU usage.So, HPA will create more pods sooner, but each pod has less CPU available.

## 2. Traffic increases 10 times by Monday. What is the plan?

1. **Add more pods:** Increase the HPA maximum limit. Check whether the pods are Ready.
2. **Add more nodes:** Increase the node group's desired and maximum size. Check whether the nodes are Ready.
3. **Increase pod resources:** Do this only if pods are running out of CPU or memory. Check using `kubectl top pods`.
4. **Increase node size:** We cannot directly make an existing node bigger. Create a new node group and move workloads from the old nodes.

## 3. App Auto Scaling vs HPA

- **App Auto Scaling:** Works outside the Kubernetes cluster. It can still work even if the cluster has problems.
- **HPA:** Works inside Kubernetes. If the cluster is broken, HPA may also stop working.
- If AWS has an outage, App Auto Scaling may stop working, but HPA can continue working if the Kubernetes cluster is still running.

## 4. HPA increases pods from 4 to 8, but 4 pods stay Pending for 20 minutes. Why?

- HPA increases the number of pods, but it does not automatically add more nodes.
- If the existing nodes do not have enough resources, the new pods stay Pending.
- **Solution:** Use Cluster Autoscaler or Karpenter to automatically add more nodes.
- Reducing CPU requests is not always a good solution because it changes how HPA calculates CPU usage and may cause it to create even more pods.

## 5. NodePort vs LoadBalancer

- **NodePort:** Opens a port (30000–32767) on every node. Users access the application through a node's IP and that port.
- **LoadBalancer:** Creates a cloud load balancer with one stable address to access the application.
- If students need to access the application using one normal address on port 80, LoadBalancer is the better choice.

## 6. Should `/enrolment` use Ingress or Gateway?

- Choose the **Gateway** approach.
- The gateway removes the `/enrolment` prefix before forwarding the request.
- It also adds the required headers.
- Direct Ingress skips these steps.
- Using one gateway gives us one place to manage access to the application.

## 7. Why did PDB not stop `kubectl delete pod`?

- **PDB (Pod Disruption Budget)** protects pods during planned maintenance.
- It controls voluntary pod removal through the eviction process, such as when draining a node.
- However, `kubectl delete pod` does not use the eviction process, so PDB cannot stop it.
- It also cannot prevent unexpected failures, such as node crashes or OOM kills.
- **Example:** During a node upgrade, PDB can prevent the last gateway pod from being evicted, helping keep the website running.

---

## Important Kubernetes Differences

| Concept | Main purpose |
|---|---|
| HPA | Adds or removes pods |
| Cluster Autoscaler | Adds or removes nodes |
| NodePort | Exposes an application through a node's IP and port |
| LoadBalancer | Provides one stable external address |
| Gateway | Controls and forwards incoming requests |
| PDB | Protects pods during planned maintenance |
