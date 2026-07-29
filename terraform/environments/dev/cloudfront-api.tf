# ─────────────────────────────────────────────────────────────────────────────
# CloudFront distribution — supervision-api (portfolio job search)
#
# Route : HTTPS (CloudFront) → HTTP (ALB interne VPC)
# Objectif : URL publique propre + arrêt automatique programmé fin décembre 2026
# Référence : output "supervision_api_cloudfront_url" → coller dans portfolio/index.html
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "supervision_api" {
  comment     = "supervision-api · Smart Assembly Line · expire 2026-12"
  enabled     = true
  price_class = "PriceClass_100" # US + Europe seulement (recruteurs ciblés)

  # ── Origine : ALB en HTTP (le TLS est géré côté CloudFront) ────────────────
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "supervision-api-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # ALB en HTTP interne, TLS terminé sur CF
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ── Comportement de cache — API temps réel, TTL minimal ────────────────────
  default_cache_behavior {
    target_origin_id       = "supervision-api-alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Accept", "Authorization"]
      cookies { forward = "none" }
    }

    # API temps réel : pas de cache côté CloudFront
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 5
  }

  # ── Pas de restriction géographique (accès recruteurs monde entier) ─────────
  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  # ── Certificat CloudFront par défaut (*.cloudfront.net) ────────────────────
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Project   = "smart-assembly-line"
    ManagedBy = "terraform"
    Expires   = "2026-12-31"
    Purpose   = "portfolio-job-search"
  }
}

# ── Output — URL à coller dans portfolio/index.html (remplace YOUR_API_CF_URL) ─
output "supervision_api_cloudfront_url" {
  description = "URL CloudFront supervision-api — remplace YOUR_API_CF_URL dans portfolio/index.html"
  value       = "https://${aws_cloudfront_distribution.supervision_api.domain_name}"
}
