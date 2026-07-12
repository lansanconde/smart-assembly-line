# Bucket principal — data lake des mesures capteurs
# Nom globalement unique dans AWS — préfixe avec l'account ID si nécessaire
resource "aws_s3_bucket" "raw_data" {
  bucket = "smart-assembly-raw-data-169237360990"

  tags = { Name = "smart-assembly-raw-data" }
}

# Versioning — protection contre suppressions accidentelles (obligatoire en contexte réglementaire)
resource "aws_s3_bucket_versioning" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Chiffrement SSE-KMS — audit complet des accès via CloudTrail
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

# Lifecycle — optimisation des coûts par classe de stockage
resource "aws_s3_bucket_lifecycle_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id
  depends_on = [aws_s3_bucket_versioning.raw_data]

  rule {
    id     = "archive-old-data"
    status = "Enabled"

    filter {} # Appliqué à tous les objets du bucket

    # Standard → Standard-IA après 30 jours (40% moins cher, accès rare)
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Standard-IA → Glacier après 90 jours (archivage réglementaire long terme)
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# Block Public Access — aucun objet ne peut être exposé publiquement, même par erreur
resource "aws_s3_bucket_public_access_block" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}