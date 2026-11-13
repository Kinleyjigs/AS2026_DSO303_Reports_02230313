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

**1. "HPA 50% = node at 50% CPU"?**
- Wrong. It is 50% of the pod's CPU **request** (50m → 25m per pod), not the node.
- Halve the request (25m) → same load looks twice as high → HPA scales out sooner, but each pod is given less CPU. Less capacity per pod, more pods.

**2. 10x traffic by Monday - plan**
1. More pods (raise HPA max) → check pods Ready, not Pending.
2. More nodes (raise node group desired/max) → check nodes Ready, Pending pods schedule.
3. Bigger pods only if pods hit their limit → check `kubectl top pods`.
4. Bigger nodes **cannot change in place** → make a new node group, drain the old one.

**3. App Auto Scaling (outside) vs HPA (inside)**
- If the cluster is broken, the HPA is broken too. App Auto Scaling keeps working outside.
- If AWS has an outage, App Auto Scaling stops, but the HPA keeps going and I can still debug it with `kubectl describe hpa`.

**4. HPA 4 → 8, four pods Pending 20 min**
- Two separate loops: HPA adds pods, but nothing adds nodes. No room → Pending.
- Fix normally comes from **Cluster Autoscaler / Karpenter** (adds nodes).
- Lowering the CPU request is bad: it changes the HPA's denominator, so it scales more aggressively and old numbers no longer compare.

**5. NodePort vs LoadBalancer**
- NodePort = a high port (30000-32767) on every node. No single address.
- LoadBalancer = NodePort + a cloud load balancer with one stable address.
- Need: "students reach it on one normal address, port 80". NodePort fails, LoadBalancer works.

**6. /enrolment via Ingress or via gateway?**
- Choose the **gateway** route. Remove `/enrolment` from the Ingress.
- The gateway strips the prefix and adds headers; the direct Ingress rule skips that.
- One entry point = one place to control access.

**7. PDB did not stop `kubectl delete pod`**
- Correct: a PDB only limits **evictions** (voluntary: drain, autoscaler). Delete does not use the eviction API.
- Involuntary (node crash, OOM, EC2 terminated) is ignored too.
- Saves production: during a node upgrade drain, the PDB stops the last gateway pod being evicted, so the site stays up.
