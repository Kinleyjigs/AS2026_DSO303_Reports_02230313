
## Step 15 - task definition revision
Block 7 shows usms-enrolment:3 rather than the lab's :2. It is the only active revision, and the service's PRIMARY deployment was created at 11:14 (+06), before the Lab 06 scalable target was registered at 13:44. No Lab 06 command passed a task definition, so this lab did not change it. The service still has one load balancer entry and one deployment.

## Step 15 - the nine-line chain
Lab 06 is responsible for three of the nine lines: the alarm fires, the policy is invoked, and the policy writes desiredCount within 2 to 10. The task start, its network placement, target registration and health checks belong to earlier labs. Block 6 shows None for the availability zone, which Floci does not report.
