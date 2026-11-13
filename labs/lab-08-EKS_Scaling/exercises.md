# Lab 08 - Exercises

### Exercise 1 - A second autoscaler
![alt text](<../../screenshots/Lab 8 screenshots/20.png>)

*Figure 1: usms-results-hpa (min 2, max 6, 60% CPU) passes the dry run and shows 2%/60% next to usms-enrolment-hpa.*

- File: `manifests/lab-08/11-hpa-results.yaml` (autoscaling/v2, no `kubectl autoscale`).
- Scale-in window 180s, scale-up max 2 pods every 30s.
- **Why 60%:** results is read-mostly and light, so each pod can work harder before adding more. Enrolment uses 50% so it scales earlier at busy times.

### Exercise 2 - Make the gateway drainable
![alt text](<../../screenshots/Lab 8 screenshots/21.png>)

*Figure 2: Gateway at 2 replicas. usms-gateway-pdb now allows 1 disruption, kubectl diff is clean and the LoadBalancer Service is unchanged.*

- **Problem:** 1 replica + `minAvailable: 1` = 0 disruptions allowed. A drain can never move it.
- **Fix:** `replicas: 2` in `manifests/lab-07/40-gateway.yaml`. The PDB was not changed.
- **One node only:** both pods are on the same node. With more nodes, I would add a `topologySpreadConstraints` on hostname to spread them.
- The old ClusterIP Service was removed from `40-gateway.yaml`, so it does not overwrite the LoadBalancer Service from Step 15.

### Exercise 3 - The autoscaler that will not act
![alt text](<../../screenshots/Lab 8 screenshots/22.png>)

*Figure 3: Diagnosis. min=max=4 gives ScalingLimited TooFewReplicas, and the pod's CPU request was copied from its limit (200m).*

![alt text](<../../screenshots/Lab 8 screenshots/23.png>)

*Figure 4: After the two fixes: request cpu 50m and maxReplicas 8, so the HPA has room to move.*

- **Fault 1 - no CPU request:** only `limits` were set, so Kubernetes copied the limit (200m) into the request. The lab expected `<unknown>`, but here the HPA worked against the wrong number (200m, not 50m). **Fix:** `requests.cpu: 50m`.
- **Fault 2 - min = max = 4:** the HPA can only ever pick 4, so it can never scale (`TooFewReplicas`). **Fix:** `maxReplicas: 8`.
- Both objects deleted afterwards.

### Exercise 4 - Expose the results service properly
![alt text](<../../screenshots/Lab 8 screenshots/24.png>)

*Figure 5: usms-results-ingress routes /results to usms-results. It shares the portal's ALB (group.name) and only allows the university network (inbound-cidrs).*

- **Design:** a second Ingress, only for `/results`, joined to the same ALB as the portal with `group.name: usms-portal`.
- **No second LoadBalancer:** each LoadBalancer Service is a new NLB and a new bill. One ALB can serve many paths.
- **Rungs:** Ingress = rung 4, usms-results Service = ClusterIP (rung 1).
- **Real EKS needs:** AWS Load Balancer Controller, `group.name` and `inbound-cidrs` annotations, `kubernetes.io/role/elb` tag on public subnets.
- **Floci:** no controller, so the Ingress has no address. Routing to usms-results tested in-cluster.
- **Cost:** one shared ALB (hourly + usage). Results adds a rule, not a load balancer.
- **If the cluster is down:** the ALB still answers but has no healthy targets, so users get 503.
- **Note:** the portal Ingress and gateway still expose `/enrolment`. In real life I would remove that path.

### Exercise 5 - Artefacts for Lab 10
![alt text](<../../screenshots/Lab 8 screenshots/25.png>)

*Figure 6: scaling-evidence JSON is valid, the readiness report is written, and both files are git-ignored by `outputs/*`.*

- **Part 1:** `outputs/lab-08-scaling-evidence.json` - HPA spec and status, enrolment replicas, node group config (2/4/2, update failed on Floci), timestamp.
- **Part 2:** `outputs/lab-08-lab06-readiness.txt`
  - Policy: USMSStudentDataReadWrite
  - Roles: usms-ec2-app-role, usms-ecs-task-role, usms-eks-node-role
  - Bucket ARN (read from the policy): `arn:aws:s3:::usms-student-data` - does not exist yet (Lab 10 creates it)
  - IRSA: annotate `usms-enrolment-sa` with `eks.amazonaws.com/role-arn` pointing to a new role (e.g. usms-enrolment-irsa-role)
  - **Not the node role:** every pod on the node shares it, so all pods would get S3 access.
- **Part 3:** written in `notes/lab-08-notes.md`.
  - **Choice:** ECS on Fargate. Small team, busy 2 months, Fargate always has room, ALB worked fully, task roles per task.
  - **Against:** Kubernetes gives more control (HPA, PDBs), one Ingress for many services, and is easier to move to another cloud.
