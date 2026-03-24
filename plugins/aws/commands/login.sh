#!/usr/bin/env bash
set -euo pipefail

# Plugin command: nixbox aws login [profile]

die() { printf '\r%s\n' "ERROR: $*" >&2; exit 1; }
log() { printf '\r%s\n' "$*"; }
log_sub() { printf '\r    %s\n' "$*"; }

# Determine profile from arg or host AWS_PROFILE
profile="${1:-${AWS_PROFILE:-}}"
[ -z "$profile" ] && die "No profile specified. Pass as argument or export AWS_PROFILE."

# Ensure authenticated
if ! aws sts get-caller-identity --profile "$profile" &>/dev/null; then
    log "==> Logging in to AWS profile '$profile'..."
    aws sso login --profile "$profile" || die "AWS SSO login failed"
fi

# Export temp credentials
log "==> Exporting credentials from profile '$profile'..."
aws_env=$(aws configure export-credentials --profile "$profile" --format env) \
    || die "Failed to export credentials"
aws_key=$(echo "$aws_env" | grep AWS_ACCESS_KEY_ID | cut -d= -f2)
aws_secret=$(echo "$aws_env" | grep AWS_SECRET_ACCESS_KEY | cut -d= -f2)
aws_token=$(echo "$aws_env" | grep AWS_SESSION_TOKEN | cut -d= -f2)

aws_region=$(aws configure get region --profile "$profile" 2>/dev/null || echo "${AWS_REGION:-eu-west-1}")

# Write to guest
log "==> Injecting AWS credentials into VM..."
nixbox run "mkdir -p ~/.aws && cat > ~/.aws/credentials <<'CREDS'
[default]
aws_access_key_id=$aws_key
aws_secret_access_key=$aws_secret
aws_session_token=$aws_token
CREDS
cat > ~/.aws/config <<'CONF'
[default]
region=$aws_region
CONF"
log_sub "AWS credentials injected (expires with SSO session)"

# ECR login — deduce registry from account ID
account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null) || true
if [ -n "$account_id" ]; then
    ecr_registry="${account_id}.dkr.ecr.${aws_region}.amazonaws.com"
    log "==> Logging into ECR ($ecr_registry)..."
    ecr_token=$(aws ecr get-login-password --profile "$profile" --region "$aws_region")
    nixbox run "echo '$ecr_token' | docker login --username AWS --password-stdin '$ecr_registry'" 2>/dev/null
    log_sub "ECR login complete"
fi
