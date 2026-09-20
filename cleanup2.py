import boto3

region = 'eu-west-3'
cw = boto3.client('cloudwatch', region_name=region)

# Supprimer composite alarms en premier
try:
    composite = cw.describe_alarms(AlarmTypes=['CompositeAlarm'])['CompositeAlarms']
    names = [a['AlarmName'] for a in composite]
    if names:
        cw.delete_alarms(AlarmNames=names)
        print(f'Composite alarms supprimees: {names}')
except Exception as e:
    print(f'Composite alarms: {e}')

# Puis toutes les metric alarms
try:
    alarms = cw.describe_alarms(AlarmTypes=['MetricAlarm'])['MetricAlarms']
    names = [a['AlarmName'] for a in alarms]
    if names:
        cw.delete_alarms(AlarmNames=names)
        print(f'Metric alarms supprimees: {names}')
    else:
        print('Aucune metric alarm restante')
except Exception as e:
    print(f'Metric alarms: {e}')

# IAM roles smart-assembly
iam = boto3.client('iam')
try:
    roles = iam.list_roles()['Roles']
    for r in roles:
        if 'smart-assembly' in r['RoleName']:
            # Detacher les policies
            attached = iam.list_attached_role_policies(RoleName=r['RoleName'])['AttachedPolicies']
            for p in attached:
                iam.detach_role_policy(RoleName=r['RoleName'], PolicyArn=p['PolicyArn'])
            # Supprimer inline policies
            inline = iam.list_role_policies(RoleName=r['RoleName'])['PolicyNames']
            for p in inline:
                iam.delete_role_policy(RoleName=r['RoleName'], PolicyName=p)
            iam.delete_role(RoleName=r['RoleName'])
            print(f'IAM role {r["RoleName"]} supprime')
except Exception as e:
    print(f'IAM: {e}')

# KMS — planifier suppression dans 7 jours (minimum AWS)
kms = boto3.client('kms', region_name=region)
try:
    keys = kms.list_keys()['Keys']
    for k in keys:
        meta = kms.describe_key(KeyId=k['KeyId'])['KeyMetadata']
        if meta['KeyManager'] == 'CUSTOMER' and meta['KeyState'] == 'Enabled':
            kms.schedule_key_deletion(KeyId=k['KeyId'], PendingWindowInDays=7)
            print(f'KMS key {k["KeyId"]} suppression planifiee dans 7 jours')
except Exception as e:
    print(f'KMS: {e}')

print('Passe 3 terminee.')
