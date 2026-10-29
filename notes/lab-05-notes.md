# Lab 05 notes

Step 10: update-service --load-balancers returned LB: null on Floci, so I used the fallback (delete + create-service with --load-balancers). Name, cluster, task def and desired count unchanged.
Floci limitation: healthCheckGracePeriodSeconds is accepted but stored as None (verify-lab-05.sh: 2 benign FAILs).
Floci limitation: targets are Docker addresses 172.20.0.x, not 10.0.3.x / 10.0.4.x; AZ shows None.
Step 12: no data path (DNS *.elb.floci does not resolve, curl 000) - control-plane proof recorded in outputs/lab-05-path-proof.txt.
Step 13: revoke by --security-group-rule-ids returned True but left the rule; revoked with --ip-permissions file://policies/usms-enrolment-sg-ingress.json instead.
Step 14: --force-new-deployment did not replace tasks on Floci; draining not observable.
Step 17: usms-web-01 was stopped after the Floci restart; started it again, then LOOP CLOSED.
Step 18: the escaped backticks in the listener line failed inside $(...); filled USMS_ALB_LISTENER_ARN by lookup with Listeners[0].

## ECS health vs target health

| ECS healthStatus | Target health | Diagnosis |
|---|---|---|
| HEALTHY | healthy | Working |
| HEALTHY | unhealthy | Network path broken: security group, subnet or health check path |
| UNHEALTHY | unhealthy | Application broken: read the container logs |
| UNKNOWN | healthy | Not a fault: no container health check in the task definition |
| anything | unused | Nothing forwards to this target group |

## Checkpoint 4 answer

Without the service registering its own targets, I would have to run register-targets / deregister-targets by hand with each new task IP after every scaling event.
