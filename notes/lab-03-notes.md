## Step 11 - key idea
USMSStudentDataReadWrite grants access to arn:aws:s3:::usms-student-data, a bucket that
does not exist yet. That is valid: an IAM policy is a statement about ARNs, not a reference
to existing objects. The permission has no effect until something exists at that ARN. When
Lab 4 runs create-bucket, the policy stops being hypothetical and usms-web-01 can write
transcripts using its instance profile - with no access key anywhere on the machine.
