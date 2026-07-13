# ──────────────────────────────────────────────
# IAM — Rôle Step Functions
# ──────────────────────────────────────────────

resource "aws_iam_role" "sfn_role" {
  name = "smart-assembly-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "smart-assembly-sfn-role"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_iam_role_policy" "sfn_policy" {
    name = "smart-assembly-sfn-policy"
    role = aws_iam_role.sfn_role.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
            Sid      = "DynamoDB"
            Effect   = "Allow"
            Action   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
            Resource = aws_dynamodb_table.machine_state.arn
            },
            {
            Sid      = "KMS"
            Effect   = "Allow"
            Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
            Resource = aws_kms_key.main.arn
            },
            {
            Sid      = "InvokeLambda"
            Effect   = "Allow"
            Action   = "lambda:InvokeFunction"
            Resource = aws_lambda_function.log_intervention.arn
            },
            {
            Sid    = "CloudWatchLogs"
            Effect = "Allow"
            Action = [
                "logs:CreateLogDelivery",
                "logs:GetLogDelivery",
                "logs:UpdateLogDelivery",
                "logs:DeleteLogDelivery",
                "logs:ListLogDeliveries",
                "logs:PutResourcePolicy",
                "logs:DescribeResourcePolicies",
                "logs:DescribeLogGroups",
            ]
            Resource = "*"
            }
        ]
    })
}

# ──────────────────────────────────────────────
# State Machine — InterventionWorkflow (Express)
# ──────────────────────────────────────────────

resource "aws_sfn_state_machine" "intervention_workflow" {
  name     = "smart-assembly-intervention-workflow"
  role_arn = aws_iam_role.sfn_role.arn
  type     = "EXPRESS"

  definition = jsonencode({
    Comment = "Workflow d'intervention suite a anomalie critique"
    StartAt = "CheckCircuitBreaker"
    States = {
      CheckCircuitBreaker = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:getItem"
        Parameters = {
          TableName = "machine_state"
          Key = {
            id_poste = { "S.$" = "$.id_poste" }
          }
        }
        ResultPath = "$.dynamodb_result"
        Next       = "EvalCircuit"
      }

      EvalCircuit = {
        Type = "Choice"
        Choices = [
          {
            And = [
              {
                Variable  = "$.dynamodb_result.Item"
                IsPresent = true
              },
              {
                Variable     = "$.dynamodb_result.Item.statut.S"
                StringEquals = "EN_INTERVENTION"
              }
            ]
            Next = "CircuitOuvert"
          }
        ]
        Default = "UpdateStatus"
      }

      CircuitOuvert = {
        Type  = "Fail"
        Error = "CircuitOpen"
        Cause = "Intervention deja en cours sur ce poste"
      }

      UpdateStatus = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = "machine_state"
          Key = {
            id_poste = { "S.$" = "$.id_poste" }
          }
          UpdateExpression = "SET statut = :s"
          ExpressionAttributeValues = {
            ":s" = { S = "EN_INTERVENTION" }
          }
        }
        ResultPath = null
        Next       = "LogIntervention"
      }

      LogIntervention = {
        Type     = "Task"
        Resource = aws_lambda_function.log_intervention.arn
        End      = true
      }
    }
  })

   logging_configuration {          # ← ajoute ici
    level                  = "ERROR"
    include_execution_data = true
    log_destination        = "${aws_cloudwatch_log_group.sfn_logs.arn}:*"
  }

  tags = {
    Name        = "smart-assembly-intervention-workflow"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_cloudwatch_log_group" "sfn_logs" {
  name              = "/aws/states/smart-assembly-intervention-workflow"
  retention_in_days = 7
}