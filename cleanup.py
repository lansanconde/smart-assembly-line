import boto3

region = 'eu-west-3'

# SQS
sqs = boto3.client('sqs', region_name=region)
for name in ['smart-assembly-vibration-queue', 'smart-assembly-vibration-dlq']:
    try:
        url = sqs.get_queue_url(QueueName=name)['QueueUrl']
        sqs.delete_queue(QueueUrl=url)
        print(f'SQS {name} supprimee')
    except Exception as e:
        print(f'SQS {name}: {e}')

# EventBridge
eb = boto3.client('events', region_name=region)
try:
    rules = eb.list_rules(NamePrefix='smart-assembly')['Rules']
    for r in rules:
        targets = eb.list_targets_by_rule(Rule=r['Name'])['Targets']
        if targets:
            eb.remove_targets(Rule=r['Name'], Ids=[t['Id'] for t in targets])
        eb.delete_rule(Name=r['Name'])
        print(f'EventBridge {r["Name"]} supprimee')
except Exception as e:
    print(f'EventBridge: {e}')

# Step Functions
sf = boto3.client('stepfunctions', region_name=region)
try:
    machines = sf.list_state_machines()['stateMachines']
    for m in machines:
        if 'smart-assembly' in m['name']:
            sf.delete_state_machine(stateMachineArn=m['stateMachineArn'])
            print(f'StepFunctions {m["name"]} supprimee')
except Exception as e:
    print(f'StepFunctions: {e}')

# CloudWatch Alarms
cw = boto3.client('cloudwatch', region_name=region)
try:
    alarms = cw.describe_alarms()['MetricAlarms']
    names = [a['AlarmName'] for a in alarms]
    if names:
        cw.delete_alarms(AlarmNames=names)
        print(f'Alarmes supprimees: {len(names)}')
except Exception as e:
    print(f'CloudWatch alarms: {e}')

# CloudWatch Dashboards
try:
    dashboards = cw.list_dashboards()['DashboardEntries']
    for d in dashboards:
        cw.delete_dashboards(DashboardNames=[d['DashboardName']])
        print(f'Dashboard {d["DashboardName"]} supprime')
except Exception as e:
    print(f'Dashboards: {e}')

# CloudWatch Log Groups
logs = boto3.client('logs', region_name=region)
try:
    groups = logs.describe_log_groups()['logGroups']
    for g in groups:
        logs.delete_log_group(logGroupName=g['logGroupName'])
        print(f'Log group {g["logGroupName"]} supprime')
except Exception as e:
    print(f'Logs: {e}')

# SNS
sns = boto3.client('sns', region_name=region)
try:
    topics = sns.list_topics()['Topics']
    for t in topics:
        if 'smart-assembly' in t['TopicArn']:
            sns.delete_topic(TopicArn=t['TopicArn'])
            print(f'SNS {t["TopicArn"]} supprime')
except Exception as e:
    print(f'SNS: {e}')

print('Passe 2 terminee.')
