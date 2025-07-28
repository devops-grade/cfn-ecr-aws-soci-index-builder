import json
import os

def handler(event, context):
  filters = event['filters']
  # Get AWS region and account ID from environment variables
  aws_region = os.environ['AWS_REGION']
  account_id = os.environ['AWS_ACCOUNT_ID']

  REPO_PREFIX = f'arn:aws:ecr:{aws_region}:{account_id}:repository/'
  repository_arns = []
  response = {}

  try:
    repositories = [filter.split(':')[0] for filter in filters]
    for repository in repositories:
      if repository == '*':
        repository_arns = [REPO_PREFIX + '*']
        break

      repository_arns.append(REPO_PREFIX + repository)

    response['repository_arns'] = repository_arns
    return {
      "statusCode": 200,
      "body": json.dumps(response)
    }
  except Exception:
    return {
      "statusCode": 500,
      "body": json.dumps(response)
    }
