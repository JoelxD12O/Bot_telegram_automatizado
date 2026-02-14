#!/usr/bin/env bash

set -euo pipefail

# Set Telegram webhook using BOT_TOKEN and the API URL from the deployed stack
# Usage: ./scripts/set_webhook.sh [stage]
# Default stage: dev

STAGE=${1:-dev}
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_ROOT"

echo "Configuring Telegram webhook (stage: $STAGE)"

# Load .env if present
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$PROJECT_ROOT/.env"
  set +a
fi

if [ -z "${BOT_TOKEN-}" ]; then
  echo "ERROR: BOT_TOKEN no definido en .env ni en el entorno. Añádelo y vuelve a intentarlo." >&2
  exit 1
fi

# Detect service name from serverless.yml
SERVICE=""
if [ -f "$PROJECT_ROOT/infra/serverless.yml" ]; then
  SERVICE=$(sed -n 's/^service:\s*//p' "$PROJECT_ROOT/infra/serverless.yml" | head -n1 | tr -d '"\r') || true
fi
SERVICE=${SERVICE:-telegram-sheets}
STACK_NAME="${SERVICE}-${STAGE}"

echo "Detected service: $SERVICE -> stack: $STACK_NAME"

# Try to read HttpApiUrl from CloudFormation outputs
API_URL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='HttpApiUrl'].OutputValue" --output text 2>/dev/null || true)

if [ -z "$API_URL" ] || [ "$API_URL" = "None" ]; then
  echo "No se pudo obtener HttpApiUrl desde CloudFormation para la stack $STACK_NAME."
  read -r -p "Introduce la URL base de la API (ej: https://...): " API_URL
  if [ -z "$API_URL" ]; then
    echo "Abortando: no se proporcionó API URL." >&2
    exit 2
  fi
fi

# Ensure no trailing slash
API_URL=${API_URL%/}
WEBHOOK_URL="$API_URL/telegram"

echo "Setting webhook to: $WEBHOOK_URL"

# Call Telegram API to set webhook
RESP=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"$WEBHOOK_URL\"}")

echo "Telegram response: $RESP"

if echo "$RESP" | grep -q '"ok":true'; then
  echo "Webhook configurado correctamente."
else
  echo "Advertencia: setWebhook devolvió un error. Revisa el response arriba." >&2
  exit 3
fi
