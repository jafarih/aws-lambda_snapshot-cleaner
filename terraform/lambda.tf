# package python file for upload
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/lambda.py"
  output_path = "${path.module}/../output/lambda.zip"
}

# policy document to allow lambda to assume role
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
# create the iam role for lambda and attach above policy f
resource "aws_iam_role" "lambda_iam_role" {
  name               = "${var.service_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# aws managed policy to allow lambda execution in vpc (needed for cloud watch logs as well). ref # https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AWSLambdaVPCAccessExecutionRole.html
resource "aws_iam_role_policy_attachment" "lambda_vpc_access_managed" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# policy document to allow lambda function to list and delete snapshots
data "aws_iam_policy_document" "snapshot_cleaner" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeSnapshots", "ec2:DeleteSnapshot"]
    resources = ["*"]
  }
}

# create policy iam policy to allow lambda function to list and delete snapshots using above document.
resource "aws_iam_policy" "snapshot_cleaner" {
  name   = "${var.service_name}-snapshot-cleanup"
  policy = data.aws_iam_policy_document.snapshot_cleaner.json
}

# add policy to allow list and deletion of snapshots to iam role for lambda
resource "aws_iam_role_policy_attachment" "snapshot_cleaner_attach" {
  role       = aws_iam_role.lambda_iam_role.name
  policy_arn = aws_iam_policy.snapshot_cleaner.arn
}

# create lambda function
resource "aws_lambda_function" "snapshot_cleaner" {
  function_name = var.service_name
  role          = aws_iam_role.lambda_iam_role.arn

  # lambda handler defined in lambda.py (file.function_name)
  handler = "lambda.lambda_handler"
  runtime = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  # to capture changes (Excludes out of bound changes) ref # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function#source_code_hash-1  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  memory_size  = 128 // default mem in MB, should be enough . cap at 10240 MB
  timeout      = 60 // in seconds. function should generally finish within one minute

  # attach lambda to security group and private subnet (defined in main.tf)
  vpc_config {
    security_group_ids = [aws_security_group.lambda_sg.id]
    subnet_ids         = [aws_subnet.private_subnet.id]
  }
  # add env vars to lambda environment. change these in Makefile
  environment {
    variables = {
      #note: not including REGION as it gets set by lambda service 
      RETENTION_HOURS = tostring(var.retention_period) # will be set to float in lambda.py
      SERVICE_NAME = var.service_name # used for logging service name in lambda.py
    }
  }

  # fail lambda if endpoint ec2 (to access snapshots) and cloud watch logging does not exist
  depends_on = [
    aws_vpc_endpoint.ec2_endpoint,
    aws_vpc_endpoint.cw_logs_endpoint
  ]
}

##########
# schedule for triggering lambda . change the lambda trigger frequency in Makefile insated
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.service_name}-schedule"
  schedule_expression = var.lambda_schedule_frequency
}

resource "aws_cloudwatch_event_target" "target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "${var.service_name}-target"
  arn       = aws_lambda_function.snapshot_cleaner.arn
}

resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snapshot_cleaner.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}