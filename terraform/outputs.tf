# enable if you want to see which profile was used at the end of each run
output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}
