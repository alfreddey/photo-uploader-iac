#!/usr/bin/env bash
# Manage the nested child templates in S3 and the TemplatesVersion pointer.
#
# Why this exists: CloudFormation Git sync deploys the root template straight
# from the repo, but the nested children must be referenced by an S3
# TemplateURL. Git sync does NOT package/upload them, and it only redeploys when
# the synced file (deployments/root.yaml) changes. The version is a content
# hash of templates/ (not a git SHA) so it is deterministic and changes only
# when the templates change.
#
# Subcommands (so the two git hooks can share this one source of truth):
#   version   print the content-hash version of templates/        (no side effects)
#   bump      write TemplatesVersion=<version> into the deploy file (no AWS)
#   upload    ensure the bucket exists and sync templates/ to S3    (no file edit)
#   all       upload then bump                                      (default; standalone use)
#
# Split across hooks: .githooks/pre-commit runs `bump` (offline, folds the bump
# into the commit); .githooks/pre-push runs `upload` (the only AWS step, right
# before the push reaches GitHub).
set -euo pipefail

REGION="${REGION:-eu-north-1}"
BUCKET="${BUCKET:-photo-uploader-cfn-templates-183631301567-eu-north-1}"
DEPLOY_FILE="${DEPLOY_FILE:-deployments/root.yaml}"

cd "$(dirname "$0")/.."

# Content hash of the child templates (name + bytes), first 12 hex chars.
version() {
  for f in $(ls templates/*.yaml | sort); do shasum -a 256 "$f"; done \
    | shasum -a 256 | cut -c1-12
}

bump() {
  local v="$1"
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i "" -E "s/^([[:space:]]*TemplatesVersion:).*/\1 ${v}/" "$DEPLOY_FILE"
  else
    sed -i -E "s/^([[:space:]]*TemplatesVersion:).*/\1 ${v}/" "$DEPLOY_FILE"
  fi
}

ensure_bucket() {
  aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null && return 0
  echo "Creating templates bucket s3://${BUCKET} ..."
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=${REGION}"
  aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
}

upload() {
  local v="$1"
  ensure_bucket
  echo "Uploading templates/ to s3://${BUCKET}/${v}/ ..."
  aws s3 sync templates/ "s3://${BUCKET}/${v}/" \
    --region "$REGION" \
    --delete \
    --exclude "*" --include "*.yaml"
}

V="$(version)"
case "${1:-all}" in
  version) echo "$V" ;;
  bump)    bump "$V"; echo "Set TemplatesVersion=${V} in ${DEPLOY_FILE}." ;;
  upload)  upload "$V"; echo "Uploaded child templates at version ${V}." ;;
  all)
    upload "$V"
    bump "$V"
    echo
    echo "Uploaded child templates at version ${V} and set TemplatesVersion=${V}."
    echo "Next: commit + push (incl. ${DEPLOY_FILE}) to trigger Git sync."
    ;;
  *) echo "usage: $0 [version|bump|upload|all]" >&2; exit 2 ;;
esac
