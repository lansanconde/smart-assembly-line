# =============================================================
# Portfolio — Smart Assembly Line
#
# Hébergement statique : S3 (privé) + CloudFront (CDN + HTTPS)
#
# Pattern :
#   S3 bucket (privé, pas de website hosting direct)
#   └── CloudFront distribution (OAC → S3)
#       └── URL publique : https://<id>.cloudfront.net
#
# Déploiement du fichier HTML :
#   aws s3 cp src/portfolio/index.html s3://<bucket>/index.html
# =============================================================

# ──────────────────────────────────────────────────────────
# S3 Bucket — contenu statique du portfolio
# Accès public désactivé : seul CloudFront peut lire le bucket
# ──────────────────────────────────────────────────────────

resource "aws_s3_bucket" "portfolio" {
  bucket = "smart-assembly-portfolio-169237360990"

  tags = {
    Name        = "smart-assembly-portfolio"
    Project     = "smart-assembly-line"
    Environment = "dev"
    Purpose     = "portfolio-static-site"
  }
}

resource "aws_s3_bucket_public_access_block" "portfolio" {
  bucket = aws_s3_bucket.portfolio.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  # Accès exclusivement via CloudFront OAC — jamais en accès public direct
}

resource "aws_s3_bucket_versioning" "portfolio" {
  bucket = aws_s3_bucket.portfolio.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ──────────────────────────────────────────────────────────
# CloudFront Origin Access Control (OAC)
# Remplace l'ancien OAI — méthode recommandée depuis 2022
# Permet à CloudFront de signer les requêtes vers S3
# ──────────────────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "portfolio" {
  name                              = "smart-assembly-portfolio-oac"
  description                       = "OAC pour le portfolio Smart Assembly Line"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always" # signer toutes les requêtes vers S3
  signing_protocol                  = "sigv4"
}

# ──────────────────────────────────────────────────────────
# CloudFront Distribution
# ──────────────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "portfolio" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "Portfolio Smart Assembly Line — Lansana CONDÉ"

  # Origin = S3 bucket (accès via OAC)
  origin {
    domain_name              = aws_s3_bucket.portfolio.bucket_regional_domain_name
    origin_id                = "S3-portfolio"
    origin_access_control_id = aws_cloudfront_origin_access_control.portfolio.id
  }

  # Comportement par défaut : cache optimisé pour les assets statiques
  default_cache_behavior {
    target_origin_id       = "S3-portfolio"
    viewer_protocol_policy = "redirect-to-https" # HTTP → HTTPS automatique

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    # Politique de cache managée "CachingOptimized" (ID AWS officiel)
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    compress = true # Gzip/Brotli automatique sur les assets texte
  }

  # Page d'erreur personnalisée : redirige 403/404 S3 vers index.html
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  # Restriction géographique : aucune (portfolio accessible mondialement)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Certificat SSL : CloudFront default (*.cloudfront.net)
  # Pour un domaine custom : remplacer par aws_acm_certificate (us-east-1 obligatoire)
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # Logs CloudFront désactivés (portfolio, pas de prod critique)
  # En production : activer avec logging_config { bucket = ... }

  price_class = "PriceClass_100" # Europe + Amérique du Nord uniquement (moins cher)

  tags = {
    Name        = "smart-assembly-portfolio-cdn"
    Project     = "smart-assembly-line"
    Environment = "dev"
    Purpose     = "portfolio-static-site"
  }
}

# ──────────────────────────────────────────────────────────
# S3 Bucket Policy — autorise CloudFront OAC uniquement
# ──────────────────────────────────────────────────────────

resource "aws_s3_bucket_policy" "portfolio" {
  bucket = aws_s3_bucket.portfolio.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontOAC"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.portfolio.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.portfolio.arn
        }
      }
    }]
  })
}

# ──────────────────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────────────────

output "portfolio_bucket_name" {
  description = "Nom du bucket S3 du portfolio"
  value       = aws_s3_bucket.portfolio.bucket
}

output "portfolio_cloudfront_domain" {
  description = "URL publique du portfolio (CloudFront)"
  value       = "https://${aws_cloudfront_distribution.portfolio.domain_name}"
}

output "portfolio_cloudfront_id" {
  description = "ID de la distribution CloudFront (pour invalidation du cache)"
  value       = aws_cloudfront_distribution.portfolio.id
}

output "portfolio_deploy_command" {
  description = "Commande pour déployer le fichier HTML"
  value       = "aws s3 cp src/portfolio/index.html s3://${aws_s3_bucket.portfolio.bucket}/index.html --content-type text/html"
}
