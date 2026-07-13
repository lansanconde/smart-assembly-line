import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sfn = boto3.client("stepfunctions")
STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]


def lambda_handler(event, context):
    processed = 0

    for record in event["Records"]:
        raw_body = record["body"]

        # Debug — voir exactement ce qui arrive depuis SQS
        logger.info(json.dumps({"debug": "raw_body", "body": raw_body}))

        body = json.loads(raw_body)

        # EventBridge envoie le payload dans "detail" (dict ou string encodée)
        if "detail" in body and isinstance(body["detail"], dict):
            detail = body["detail"]
        elif "detail" in body and isinstance(body["detail"], str):
            detail = json.loads(body["detail"])
        else:
            detail = body

        id_poste = detail.get("id_poste", "unknown")
        execution_name = f"intervention-{id_poste}-{record['messageId'][:8]}"

        sfn_input = json.dumps(detail)
        logger.info(json.dumps({
            "action":        "start_execution",
            "id_poste":      id_poste,
            "execution":     execution_name,
            "sfn_input":     sfn_input,
        }))

        sfn.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            name=execution_name,
            input=sfn_input,
        )

        processed += 1

    return {"statusCode": 200, "processed": processed}