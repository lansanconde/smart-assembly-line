# X-Ray — Config Terraform

```hcl
# Lambda — active tracing
resource "aws_lambda_function" "analyze_vibration" {
  tracing_config {
    mode = "Active"
  }
}

# X-Ray sampling rule
resource "aws_xray_sampling_rule" "analyze_vibration" {
  rule_name      = "analyze-vibration-sampling"
  priority       = 1000
  reservoir_size = 1
  fixed_rate     = 0.10   # 10%
  service_name   = "analyze_vibration"
  service_type   = "AWS::Lambda::Function"
  host           = "*"
  http_method    = "*"
  url_path       = "*"
  version        = 1
}
```

IAM requis sur le rôle Lambda :
```json
{ "Effect": "Allow", "Action": ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], "Resource": "*" }
```
