# Lab 07 - Exercises

### Exercise 1
![alt text](<../../screenshots/Lab 7 screenshots/34.png>)

*Figure 1: usms-timetable is deployed from one file (ConfigMap, Deployment and Service). There are now four Deployments and four Services, and a busybox pod gets JSON from it by DNS name.*

### Exercise 2
![alt text](<../../screenshots/Lab 7 screenshots/35.png>)

*Figure 2: After adding the /timetable/ route and running `kubectl rollout restart`, the gateway is on a new ReplicaSet (revision 2) and all three routes return JSON.*

Applying the file only changed the ConfigMap, so `/timetable/` still gave 404. `kubectl rollout restart` created the new pod that loaded the new route.

### Exercise 3
![alt text](<../../screenshots/Lab 7 screenshots/36.png>)

*Figure 3: The pods are 0/1 Ready because the probe gets 404 on /healthz, and the Service has no endpoints because it selects version v2 while the pods are v1.*

![alt text](<../../screenshots/Lab 7 screenshots/37.png>)

*Figure 4: After two one-line fixes, both pods are Ready, the Service has two endpoints and it serves the nginx page.*

**Fault 1:** the readiness probe checks `/healthz`, which plain nginx does not serve, so the pods never become Ready. Found with `kubectl describe pod`. Fix: `path: /`.
**Fault 2:** the Service selects `version: v2` but the pods are `v1`. Found by comparing the Service selector with `kubectl get pods --show-labels`. Fix: `version: v1`.

### Exercise 4
![alt text](<../../screenshots/Lab 7 screenshots/38.png>)

*Figure 5: usms-enrolment has a topology spread constraint and a PodDisruptionBudget (minAvailable 1). `get pods -o wide` shows each pod's node.*

![alt text](<../../screenshots/Lab 7 screenshots/39.png>)

*Figure 6: During a drain, the PDB allowed one pod to be evicted and blocked the second, so one pod kept answering all requests.*

The cluster has only one node, so the pods cannot be spread across nodes. The **topology spread** constraint is advisory: it would spread pods over several nodes but does not block them here. The **PodDisruptionBudget** is enforced: it stopped the drain from removing the last pod. With more nodes, the evicted pod would move to another node and the service would never go down.

### Exercise 5
![alt text](<../../screenshots/Lab 7 screenshots/40.png>)

*Figure 7: Each enrolment pod uses 1m CPU (2% of its 50m request). USMSStudentDataReadWrite is held by three roles, and its bucket usms-student-data does not exist yet. Both files are git-ignored.*

Lab 08 needs the cluster, node group, namespace, LB ports, endpoint, enrolment and gateway names, and the 50m CPU request. These are listed in `notes/lab-07-notes.md`.
