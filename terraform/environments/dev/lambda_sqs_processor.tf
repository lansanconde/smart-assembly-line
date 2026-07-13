# ──────────────────────────────────────────────
# Lambda — LogIntervention
# ──────────────────────────────────────────────

data "archive_file" "log_intervention_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../src/lambda/log_intervention/handler.py"
  output_path = "${path.module}/log_intervention.zip"
}

resource "aws_lambda_function" "log_intervention" {
  function_name    = "smart-assembly-log-intervention"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.log_intervention_zip.output_path
  source_code_hash = data.archive_file.log_intervention_zip.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.machine_state.name
    }
  }

  tags = {
    Name        = "smart-assembly-log-intervention"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_cloudwatch_log_group" "log_intervention" {
  name              = "/aws/lambda/smart-assembly-log-intervention"
  retention_in_days = 7
}

# ──────────────────────────────────────────────
# Lambda — SQSProcessor
# ──────────────────────────────────────────────

data "archive_file" "sqs_processor_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../src/lambda/sqs_processor/handler.py"
  output_path = "${path.module}/sqs_processor.zip"
}

resource "aws_lambda_function" "sqs_processor" {
  function_name    = "smart-assembly-sqs-processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.sqs_processor_zip.output_path
  source_code_hash = data.archive_file.sqs_processor_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.intervention_workflow.arn
    }
  }

  tags = {
    Name        = "smart-assembly-sqs-processor"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_cloudwatch_log_group" "sqs_processor" {
  name              = "/aws/lambda/smart-assembly-sqs-processor"
  retention_in_days = 7
}

# SQS → Lambda trigger
resource "aws_lambda_event_source_mapping" "sqs_to_processor" {
  event_source_arn = aws_sqs_queue.intervention.arn
  function_name    = aws_lambda_function.sqs_processor.arn
  batch_size       = 1
  enabled          = true
}

# ──────────────────────────────────────────────
# IAM — Permissions supplémentaires pour le rôle Lambda
# ──────────────────────────────────────────────

resource "aws_iam_role_policy" "lambda_sfn_policy" {
  name = "smart-assembly-lambda-sfn-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartStepFunctions"
        Effect = "Allow"
        Action = "states:StartExecution"
        Resource = aws_sfn_state_machine.intervention_workflow.arn
      },
      {
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
        ]
        Resource = aws_sqs_queue.intervention.arn
      }
    ]
  })
}