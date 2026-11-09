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

## Step 6 "Your turn": widening the health check matcher

Changed the matcher with modify-target-group from HttpCode=200 to 200-399, read it back
(describe-target-groups showed 200-399), then restored it to 200 (confirmed). No
recreation was needed; the change applies immediately.

(a) A web application that answers GET / with a 301 or 302 redirect, for example one that
    redirects "/" to "/login" or forces HTTP to HTTPS, would be reported unhealthy forever
    under a strict 200 matcher even though it is serving users correctly.

(b) It would be a bug in the script, not in my work. A verification script exists to check
    that the deployed state meets the intended design, and 200-399 is a valid, working
    configuration; asserting one exact value turns a deliberate choice into a false failure.
    The honest fix is to have the script check the property that matters (the health check
    reports healthy targets, or the matcher falls in an accepted set), or to record the
    intended value in the lab so the script and the design stay in sync.

## Step 11 "Your turn": desired count 3, then back to 2

Raised desiredCount to 3 with update-service; the target group went from two targets to three
and back to two with no register-targets or deregister-targets call from me.

Answer: after every scaling event I would have had to run register-targets (or
deregister-targets) by hand with each new or removed task's IP address, because without the
service's load balancer link the target group would not track the tasks that come and go.
