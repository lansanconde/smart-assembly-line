# ──────────────────────────────────────────────
# Packaging ZIP des fonctions Lambda
# ──────────────────────────────────────────────

data "archive_file" "analyze_vibration_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../src/lambda/analyze_vibration/handler.py"
  output_path = "${path.module}/../../../src/lambda/analyze_vibration/handler.zip"
}

data "archive_file" "store_metrics_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../src/lambda/store_metrics/handler.py"
  output_path = "${path.module}/../../../src/lambda/store_metrics/handler.zip"
}

# ──────────────────────────────────────────────
# Lambda — AnalyzeVibration
# ──────────────────────────────────────────────

resource "aws_lambda_function" "analyze_vibration" {
  function_name    = "smart-assembly-analyze-vibration"
  description      = "Analyse les métriques capteurs et met à jour l'état DynamoDB"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.analyze_vibration_zip.output_path
  source_code_hash = data.archive_file.analyze_vibration_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.machine_state.name
    }
  }

  tags = {
    Project     = "smart-assembly-line"
    Environment = "dev"
    Function    = "analyze-vibration"
  }
}

resource "aws_lambda_permission" "iot_invoke_analyze" {

  statement_id  = "AllowIoTInvokeAnalyze"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analyze_vibration.function_name
  principal     = "iot.amazonaws.com"
}

# ──────────────────────────────────────────────
# Lambda — StoreMetrics
# ──────────────────────────────────────────────

resource "aws_lambda_function" "store_metrics" {
  function_name    = "smart-assembly-store-metrics"
  description      = "Archive les messages capteurs bruts dans S3"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.store_metrics_zip.output_path
  source_code_hash = data.archive_file.store_metrics_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.raw_data.id
    }
  }

  tags = {
    Project     = "smart-assembly-line"
    Environment = "dev"
    Function    = "store-metrics"
  }
}

resource "aws_lambda_permission" "iot_invoke_store" {
  statement_id  = "AllowIoTInvokeStore"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.store_metrics.function_name
  principal     = "iot.amazonaws.com"
}


# ──────────────────────────────────────────────
# Lambda — DetectAnomaly
# ──────────────────────────────────────────────

data "archive_file" "detect_anomaly_zip" {
  type        = "zip"
  source_file = "${path.module}/../../../src/lambda/detect_anomaly/handler.py"
  output_path = "${path.module}/../../../src/lambda/detect_anomaly/handler.zip"
}

resource "aws_lambda_function" "detect_anomaly" {
  function_name    = "smart-assembly-detect-anomaly"
  description      = "Regles metier avancees — publie sur EventBridge"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.detect_anomaly_zip.output_path
  source_code_hash = data.archive_file.detect_anomaly_zip.output_base64sha256

  environment {
    variables = {
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.main.name
      TABLE_NAME     = aws_dynamodb_table.machine_state.name
    }
  }

  tags = {
    Name        = "smart-assembly-detect-anomaly"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_lambda_permission" "iot_invoke_detect" {
  statement_id  = "AllowIoTInvokeDetect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.detect_anomaly.function_name
  principal     = "iot.amazonaws.com"
}