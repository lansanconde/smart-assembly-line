# resource "aws_kinesis_stream" "sensors" {
#   name             = "smart-assembly-sensors"
#   shard_count      = 1
#   retention_period = 24
#
#   stream_mode_details {
#     stream_mode = "PROVISIONED"
#   }
#
#   encryption_type = "KMS"
#   kms_key_id      = aws_kms_key.main.id
#
#   tags = { Name = "smart-assembly-sensors" }
# }