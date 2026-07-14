# Table DynamoDB — état temps réel de chaque poste d'assemblage
# Un item par poste, écrasé à chaque message capteur
resource "aws_dynamodb_table" "machine_state" {
  name         = "machine_state"
  billing_mode = "PAY_PER_REQUEST"  # On-demand : facturation à la requête, pas de capacité à provisionner



  # Partition key = id_poste : distribution équitable, pas de hot partition
  hash_key = "id_poste"

  attribute {
    name = "id_poste"
    type = "S"  # S = String
  }

  attribute {
    name = "statut"
    type = "S"
  }

  global_secondary_index {
    name            = "statut-index"
    hash_key        = "statut"
    projection_type = "ALL"
  }

  # Chiffrement at-rest avec clé KMS gérée par AWS
  server_side_encryption {
    enabled = true
    kms_key_arn = aws_kms_key.main.arn
  }

  # Point-in-time recovery — restauration possible à n'importe quel moment des 35 derniers jours
  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "smart-assembly-machine-state" }
}

