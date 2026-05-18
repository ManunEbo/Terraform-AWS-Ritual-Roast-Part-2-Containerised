import boto3
import json
import logging
import random
import string
import pymysql # Pulled from the Lambda Layer

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def generate_random_password(length=16):
    characters = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(random.choices(characters, k=length))

def lambda_handler(event, context):
    arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']

    client = boto3.client('secretsmanager')

    metadata = client.describe_secret(SecretId=arn)
    if not metadata['RotationEnabled']:
        logger.error(f"Secret {arn} is not enabled for rotation")
        raise ValueError(f"Secret {arn} is not enabled for rotation")

    if step == "createSecret":
        create_secret(client, arn, token)
    elif step == "setSecret":
        set_secret(client, arn, token)
    elif step == "testSecret":
        test_secret(client, arn, token)
    elif step == "finishSecret":
        finish_secret(client, arn, token)
    else:
        msg = f"Invalid step parameter: {step}"
        logger.error(msg)
        raise ValueError(msg)

def create_secret(client, arn, token):
    current_dict = get_secret_dict(client, arn, "AWSCURRENT")
    current_dict['password'] = generate_random_password()
    
    try:
        client.put_secret_value(
            SecretId=arn,
            ClientRequestToken=token,
            SecretString=json.dumps(current_dict),
            VersionStages=['AWSPENDING']
        )
    except client.exceptions.ResourceExistsException:
        pass

def set_secret(client, arn, token):
    current_dict = get_secret_dict(client, arn, "AWSCURRENT")
    pending_dict = get_secret_dict(client, arn, "AWSPENDING", token)

    host = current_dict['host']
    db_name = current_dict['dbname']
    username = current_dict['username']
    new_password = pending_dict['password']

    try:
        conn = pymysql.connect(
            host=host,
            user=username,
            password=current_dict['password'], # Log in with old password
            database=db_name,
            connect_timeout=5
        )
        with conn.cursor() as cursor:
            # Change password directly
            cursor.execute(f"ALTER USER '{username}'@'%' IDENTIFIED BY '{new_password}';")
        conn.commit()
        conn.close()
    except Exception as e:
        logger.error(f"Failed to update database password: {e}")
        raise

def test_secret(client, arn, token):
    pending_dict = get_secret_dict(client, arn, "AWSPENDING", token)
    
    try:
        conn = pymysql.connect(
            host=pending_dict['host'],
            user=pending_dict['username'],
            password=pending_dict['password'],
            database=pending_dict['dbname'],
            connect_timeout=5
        )
        conn.close()
    except Exception as e:
        logger.error(f"Failed to connect with new password: {e}")
        raise

def finish_secret(client, arn, token):
    metadata = client.describe_secret(SecretId=arn)
    current_version = None
    for version in metadata.get("VersionIdsToStages", {}):
        if "AWSCURRENT" in metadata["VersionIdsToStages"][version]:
            if version == token:
                return # Already the active version
            current_version = version
            break

    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version
    )

def get_secret_dict(client, arn, stage, token=None):
    if token:
        response = client.get_secret_value(SecretId=arn, VersionId=token, VersionStage=stage)
    else:
        response = client.get_secret_value(SecretId=arn, VersionStage=stage)
    return json.loads(response['SecretString'])