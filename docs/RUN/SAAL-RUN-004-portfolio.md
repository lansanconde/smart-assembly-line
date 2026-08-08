# Runbook — Portfolio AWS

## Déployer le portfolio

```powershell
# Upload vers S3
aws s3 cp src/portfolio/index.html s3://smart-assembly-portfolio-169237360990/index.html `
  --content-type text/html --region eu-west-3

# Invalider le cache CloudFront
aws cloudfront create-invalidation `
  --distribution-id E271YNMVZ3GMXD --paths "/*"
```

## URLs
| Ressource | URL |
|-----------|-----|
| Portfolio | https://do1vmragia1j9.cloudfront.net |
| S3 bucket | `smart-assembly-portfolio-169237360990` |
| Distribution ID | `E271YNMVZ3GMXD` |
