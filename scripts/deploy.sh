#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Starting deployment process..."

# Navigate to project root
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

echo "Using project root: $PROJECT_ROOT"

# If a .env file exists in the project root, load its variables so changes
# in .env are reflected when the script runs.
if [ -f "$PROJECT_ROOT/.env" ]; then
  echo "Cargando variables desde $PROJECT_ROOT/.env"
  # Export all variables defined in .env for use in this script
  set -a
  # shellcheck disable=SC1090
  . "$PROJECT_ROOT/.env"
  set +a
fi

# Short explanation for the user (in Spanish):
echo ""
echo "Sobre SPREADSHEET_ID:"
echo "  - Es el identificador único de tu Google Spreadsheet."
echo "  - Lo puedes obtener de la URL de la hoja. Ejemplo de URL:"
echo "      https://docs.google.com/spreadsheets/d/<SPREADSHEET_ID>/edit"
echo "  - Puedes pegar aquí la URL completa o solo el ID cuando se te pida."
echo ""

# If SPREADSHEET_ID not set, prompt the user and export it for the rest of the script
if [ -z "${SPREADSHEET_ID-}" ]; then
  echo "SPREADSHEET_ID no detectado en el entorno. Puedes pegar la URL completa o el ID ahora."
  read -r -p "Introduce Spreadsheet URL o ID (o deja vacío para abortar): " INPUT
  if [ -z "$INPUT" ]; then
    echo "Aborting: SPREADSHEET_ID no proporcionado." >&2
    exit 5
  fi

  # Try to extract ID from a URL; if not found, assume input is the ID
  EXTRACTED_ID=$(printf "%s" "$INPUT" | sed -n 's,.*/d/\([^/]*\).* ,\1,p' | tr -d '\n' || true)
  if [ -z "$EXTRACTED_ID" ]; then
    # second sed variant (in case of no trailing slash)
    EXTRACTED_ID=$(printf "%s" "$INPUT" | sed -n 's,.*/d/\([^/?]*\).* ,\1,p' | tr -d '\n' || true)
  fi
  if [ -z "$EXTRACTED_ID" ]; then
    # fallback: assume the user supplied the ID directly
    EXTRACTED_ID="$INPUT"
  fi

  # Trim whitespace
  EXTRACTED_ID=$(printf "%s" "$EXTRACTED_ID" | tr -d '[:space:]')
  if [ -z "$EXTRACTED_ID" ]; then
    echo "No se pudo determinar un SPREADSHEET_ID válido. Abortando." >&2
    exit 6
  fi

  export SPREADSHEET_ID="$EXTRACTED_ID"
  echo "SPREADSHEET_ID exportado: $SPREADSHEET_ID"
  # Guardar SPREADSHEET_ID en .env en la raíz del proyecto para uso futuro
  ENV_FILE="$PROJECT_ROOT/.env"
  echo "Guardando SPREADSHEET_ID en $ENV_FILE"
  # Crear .env si no existe
  touch "$ENV_FILE"
  # Si ya existe la variable, reemplazarla; si no, añadirla
  if grep -qE '^SPREADSHEET_ID=' "$ENV_FILE" 2>/dev/null; then
    # Reemplaza la línea existente de forma segura
    sed -i.bak -E "s/^SPREADSHEET_ID=.*/SPREADSHEET_ID=\"$EXTRACTED_ID\"/" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    printf "SPREADSHEET_ID=\"%s\"\n" "$EXTRACTED_ID" >> "$ENV_FILE"
  fi
  echo ".env actualizado. (Asegúrate de no subirlo a repositorios públicos.)"
else
  echo "SPREADSHEET_ID detectado en entorno: $SPREADSHEET_ID"
fi

# Validate BOT_TOKEN exists (required for serverless.yml)
if [ -z "${BOT_TOKEN-}" ]; then
  echo "ERROR: BOT_TOKEN no definido en el entorno. Añádelo en .env o exporta la variable." >&2
  echo "Ejemplo: echo 'BOT_TOKEN=\"tu_token_aqui\"' >> .env" >&2
  exit 10
fi

echo ""
# Verify required CLIs
command -v npx >/dev/null 2>&1 || { echo "ERROR: 'npx' not found. Instala Node/npm o entra en nix-shell con node disponible." >&2; exit 2; }
command -v aws >/dev/null 2>&1 || { echo "ERROR: 'aws' CLI not found. Instala y configura AWS CLI." >&2; exit 3; }

# Verify AWS identity
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS CLI no puede autenticarse. Ejecuta 'aws configure' o setea credenciales." >&2
  exit 4
fi

echo "Tooling checks passed: npx and aws available."

# Check credentials file
if [ ! -f "$PROJECT_ROOT/config/credentials.json" ]; then
  echo "ERROR: Google Service Account credentials not found at '$PROJECT_ROOT/config/credentials.json'." >&2
  echo "Place the JSON file (service account) at that path before deploying." >&2
  exit 7
fi

echo "Environment and credentials verified."

# Ensure infra/config contains credentials.json for Serverless packaging
if [ -f "$PROJECT_ROOT/config/credentials.json" ]; then
  mkdir -p "$PROJECT_ROOT/infra/config"
  cp -f "$PROJECT_ROOT/config/credentials.json" "$PROJECT_ROOT/infra/config/credentials.json"
  echo "Copied $PROJECT_ROOT/config/credentials.json -> $PROJECT_ROOT/infra/config/credentials.json for packaging"
fi

# Check serverless-python-requirements dockerizePip setting
DOCKERIZE=false
if grep -q "dockerizePip:\s*true" "$PROJECT_ROOT/infra/serverless.yml" 2>/dev/null; then
  DOCKERIZE=true
fi
if [ "$DOCKERIZE" = true ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: serverless-python-requirements requires Docker (dockerizePip: true) but docker is not available." >&2
    echo "Install Docker or set dockerizePip: false in infra/serverless.yml." >&2
    exit 8
  fi
  echo "Docker present and required by serverless config."
fi

echo "Installing Serverless plugin (if missing)..."
cd "$PROJECT_ROOT/infra"
if ! npm install --no-audit --no-fund --save-dev serverless-python-requirements >/dev/null 2>&1; then
  echo "Warning: npm install for serverless-python-requirements failed or produced warnings. Proceeding, but packaging may fail." >&2
fi

echo ""
echo "SPREADSHEET_ID actual: $SPREADSHEET_ID"
echo "BOT_TOKEN: set"
echo "Deploying with Serverless (this will run 'npx serverless deploy --verbose')..."
npx serverless deploy --verbose

echo "Deployment finished. Check the output above for 'endpoints:' and the API Gateway URL."
echo "Invocando script para configurar webhook de Telegram..."
if [ -x "$PROJECT_ROOT/scripts/set_webhook.sh" ]; then
  # Pass no args (default stage 'dev')
  "$PROJECT_ROOT/scripts/set_webhook.sh" || echo "Advertencia: set_webhook.sh falló. Revisa su salida." >&2
else
  echo "Advertencia: $PROJECT_ROOT/scripts/set_webhook.sh no existe o no es ejecutable. Salta la configuración automática del webhook." >&2
fi
