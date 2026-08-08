# Runbook — Portfolio API + CloudFront

## CloudFront distributions

| Distribution | ID | URL |
|-------------|-----|-----|
| Portfolio | `E271YNMVZ3GMXD` | do1vmragia1j9.cloudfront.net |
| API | (voir console) | dv03heuf7nfn6.cloudfront.net |

## Déployer une mise à jour portfolio
```powershell
# 1. Upload
aws s3 cp src/portfolio/index.html `
  s3://smart-assembly-portfolio-169237360990/index.html `
  --content-type text/html --region eu-west-3

# 2. Invalider cache (propagation ~1 min)
aws cloudfront create-invalidation `
  --distribution-id E271YNMVZ3GMXD --paths "/*"
```

## Auto-expiry 31 décembre 2026
Lambda `cf_expiry` déclenché par EventBridge Scheduler :
- `desired_count = 0` sur ECS
- CloudFront API → `Enabled: false`
