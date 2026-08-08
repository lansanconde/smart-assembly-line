# Runbook — Sécurité avancée

## Déploiement GuardDuty + Security Hub + Config
```bash
terraform apply -target=aws_guardduty_detector.main \
                -target=aws_securityhub_account.main \
                -target=aws_config_configuration_recorder.main
```

## Vérifier les findings GuardDuty
```bash
aws guardduty list-findings \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text) \
  --region eu-west-3
```

## Score Security Hub
Console → Security Hub → Summary → Security score
