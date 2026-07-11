resource "aws_iam_role" "lambda_role" {
  name = "smart-assembly-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Role pour IoT Core
resource "aws_iam_role" "iot_role" {
  name = "smart-assembly-iot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "iot.amazonaws.com" }
    }]
  })
}

# Permissions DynamoDB pour Lambda
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "smart-assembly-lambda-dynamodb"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.machine_state.arn
      }
    ]
  })
}

# Permissions S3 pour Lambda
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "smart-assembly-lambda-s3"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.raw_data.arn}/*"
      }
    ]
  })
}