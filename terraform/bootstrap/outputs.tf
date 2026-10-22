output "state_bucket_name" {
  description = "Set this value as the TF_STATE_BUCKET GitHub Actions secret."
  value       = aws_s3_bucket.state.bucket
}

output "plan_user_name" {
  description = "IAM user for PR plans; create its access key outside Terraform."
  value       = aws_iam_user.plan.name
}

output "apply_user_name" {
  description = "IAM user for main-branch applies; create its access key outside Terraform."
  value       = aws_iam_user.apply.name
}
