#!/usr/bin/env bash
# Regenerate taskdef.json from the live task definition and upload
# deploy-config.zip to the artifact bucket.
#
# Run this after every stack tear-down/recreate, once the root stack (and its
# compute nested stack) is CREATE_COMPLETE: the task definition's environment
# values (RDS endpoint, secret ARN, CloudFront domain) are stack-generated and
# change each cycle, so the zip must be rebuilt from the live revision rather
# than from a committed copy. The pipeline's S3 source action
# (templates/pipeline.yaml) fails with "object not found" until this object
# exists.
set -euo pipefail

REGION="${REGION:-eu-north-1}"
FAMILY="${FAMILY:-photo-uploader-dev}"
BUCKET="${BUCKET:-photo-uploader-dev-artifacts-183631301567}"
KEY="${KEY:-deploy/deploy-config.zip}"

cd "$(dirname "$0")"

aws ecs describe-task-definition \
  --region "$REGION" \
  --task-definition "$FAMILY" \
  --query 'taskDefinition' --output json \
| jq '{
    family,
    networkMode,
    requiresCompatibilities,
    cpu,
    memory,
    executionRoleArn,
    taskRoleArn,
    containerDefinitions: [.containerDefinitions[] | {
      name,
      image: "<IMAGE1_NAME>",
      essential,
      portMappings: [.portMappings[] | {containerPort, protocol}],
      environment,
      secrets,
      logConfiguration: {logDriver: .logConfiguration.logDriver, options: .logConfiguration.options}
    }]
  }' > taskdef.json

rm -f deploy-config.zip
zip -q deploy-config.zip appspec.yaml taskdef.json
aws s3 cp deploy-config.zip "s3://${BUCKET}/${KEY}" --region "$REGION"
echo "Uploaded s3://${BUCKET}/${KEY} (taskdef derived from ${FAMILY} latest revision)"
