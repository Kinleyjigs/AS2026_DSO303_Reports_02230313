# Lab 04 notes

Support path: A (full). ECS and Application Auto Scaling both answer.
Limitation recorded: application-autoscaling describe-scheduled-actions returns
UnsupportedOperation on this Floci build. Real AWS supports scheduled scaling.
Probe note: the lab's probe reports "ecs describe-services: not available" because it
treats ClusterNotFoundException (exit code 254) as a failure. ECS did answer, so the
operation is supported.
