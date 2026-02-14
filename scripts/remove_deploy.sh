#!/usr/bin/env bash

set -euo pipefail

chmod +x "$0" 2>/dev/null || true

#!/usr/bin/env bash

set -euo pipefail

# Script seguro para eliminar el despliegue Serverless del proyecto
# - Limpia el prefijo serverless/ en el bucket de deployment
# - Soporta buckets con versionado (borra versiones/delete-markers)
# - Ejecuta `npx serverless remove --stage <stage>` con SPREADSHEET_ID en el entorno

# Usage: ./scripts/remove_deploy.sh [stage]
# Default stage: dev

STAGE=${1:-dev}
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$PROJECT_ROOT"

echo "Project root: $PROJECT_ROOT"
echo "Stage a eliminar: $STAGE"

# Cargar .env si existe
if [ -f "$PROJECT_ROOT/.env" ]; then
  echo "Cargando variables desde $PROJECT_ROOT/.env"
  set -a
  # shellcheck disable=SC1090
  . "$PROJECT_ROOT/.env"
  set +a
fi

# Herramientas requeridas
command -v npx >/dev/null 2>&1 || { echo "ERROR: 'npx' no encontrado. Instala Node/npm." >&2; exit 2; }
command -v aws >/dev/null 2>&1 || { echo "ERROR: 'aws' CLI no encontrado. Instala y configura AWS CLI." >&2; exit 3; }

# Verificar autenticación AWS
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS CLI no puede autenticarse. Ejecuta 'aws configure' o setea credenciales." >&2
  exit 4
fi

# Detectar nombre de servicio desde infra/serverless.yml (campo 'service:')
SERVICE=""
if [ -f "$PROJECT_ROOT/infra/serverless.yml" ]; then
  SERVICE=$(sed -n 's/^service:\s*//p' "$PROJECT_ROOT/infra/serverless.yml" | head -n1 | tr -d '"\r') || true
fi
SERVICE=${SERVICE:-telegram-sheets}
STACK_NAME="${SERVICE}-${STAGE}"

echo "Service detectado: $SERVICE"
echo "Stack CloudFormation: $STACK_NAME"

# Obtener el nombre del bucket de deployment desde Outputs
BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='ServerlessDeploymentBucketName'].OutputValue" --output text 2>/dev/null || true)

if [ -z "$BUCKET" ] || [ "$BUCKET" = "None" ]; then
  echo "No se pudo detectar automáticamente el bucket de deployment para la stack $STACK_NAME." >&2
  read -r -p "Introduce el nombre del bucket S3 de deployment (o deja vacío para abortar): " BUCKET
  if [ -z "$BUCKET" ]; then
    echo "Abortando: no se proporcionó bucket." >&2
    exit 5
  fi
fi

echo "Bucket de deployment detectado/seleccionado: $BUCKET"

# Prefijo a limpiar
PREFIX="serverless/"

# Listar contenido del prefijo
echo "Contenido actual de s3://$BUCKET/$PREFIX (si existe):"
aws s3 ls "s3://$BUCKET/$PREFIX" --recursive || echo "(prefijo vacío o inaccesible)"

read -r -p "¿Quieres borrar recursivamente el prefijo '$PREFIX' en s3://$BUCKET/? [y/N]: " CONFIRM
if [ "${CONFIRM,,}" != "y" ]; then
  echo "Operación cancelada por usuario." && exit 0
fi

# Borrar objetos normales en el prefijo
echo "Borrando objetos en s3://$BUCKET/$PREFIX ..."
aws s3 rm "s3://$BUCKET/$PREFIX" --recursive || echo "Advertencia: aws s3 rm devolvió error o no había objetos."

# Verificar versionado
VER_STATUS=$(aws s3api get-bucket-versioning --bucket "$BUCKET" --query 'Status' --output text 2>/dev/null || echo "")
if [ "$VER_STATUS" = "Enabled" ]; then
  echo "Bucket con versionado habilitado. Eliminando versiones y delete-markers en prefix $PREFIX"
  TMP_VERSIONS=$(mktemp /tmp/versions.XXXXXX.json)
  TMP_DELETE=$(mktemp /tmp/delete_payload.XXXXXX.json)
  aws s3api list-object-versions --bucket "$BUCKET" --prefix "$PREFIX" --output json > "$TMP_VERSIONS" || true

  python3 - <<'PY' > /dev/null 2>&1 || true
import json,sys
try:
    j=json.load(open('$TMP_VERSIONS'))
except Exception:
    j={}
objs=[]
for v in j.get('Versions',[]):
    objs.append({'Key':v['Key'],'VersionId':v['VersionId']})
for dm in j.get('DeleteMarkers',[]):
    objs.append({'Key':dm['Key'],'VersionId':dm['VersionId']})
if objs:
    open('$TMP_DELETE','w').write(json.dumps({'Objects':objs,'Quiet':False}))
    print('HAS_PAYLOAD')
else:
    print('NO_OBJECTS')
PY

  # Leer resultado para decidir
  if grep -q HAS_PAYLOAD "$TMP_DELETE" 2>/dev/null; then
    # actually delete
    echo "Eliminando versiones/delete-markers (via s3api delete-objects)..."
    aws s3api delete-objects --bucket "$BUCKET" --delete file://"$TMP_DELETE" || echo "Advertencia: eliminación de versiones devolvió error."
  else
    echo "No se encontraron versiones/delete-markers para el prefijo $PREFIX"
  fi

  rm -f "$TMP_VERSIONS" "$TMP_DELETE" || true
fi

# Confirmar prefijo vacío
echo "Comprobando que el prefijo quedó vacío:"
if aws s3 ls "s3://$BUCKET/$PREFIX" --recursive | grep -q .; then
  echo "ADVERTENCIA: el prefijo $PREFIX todavía contiene objetos. Revisa manualmente."
else
  echo "Prefijo $PREFIX vacío (o no encontrado)."
fi

# Ejecutar serverless remove con las variables SPREADSHEET_ID y BOT_TOKEN (si existen)
if [ -z "${SPREADSHEET_ID-}" ]; then
  echo "SPREADSHEET_ID no definido en el entorno. Se te pedirá que lo ingreses para el comando 'serverless remove'."
  read -r -p "Introduce SPREADSHEET_ID (o deja vacío para abortar): " INPUT_ID
  if [ -z "$INPUT_ID" ]; then
    echo "Abortando: SPREADSHEET_ID no proporcionado." >&2
    exit 6
  fi
  export SPREADSHEET_ID="$INPUT_ID"
fi

if [ -z "${BOT_TOKEN-}" ]; then
  echo "WARNING: BOT_TOKEN no definido. Si serverless.yml lo requiere, el remove fallará." >&2
  echo "Considera añadirlo en .env antes de ejecutar este script." >&2
fi

echo "Ejecutando: SPREADSHEET_ID=*** BOT_TOKEN=*** npx serverless remove --stage $STAGE (credenciales ocultas)"
# Ensure we run the Serverless command from the infra/ directory where serverless.yml lives
if [ -d "$PROJECT_ROOT/infra" ]; then
  cd "$PROJECT_ROOT/infra"
  echo "Directorio actual: $(pwd)"
  if [ ! -f "serverless.yml" ]; then
    echo "ERROR: no se encontró 'serverless.yml' en $PROJECT_ROOT/infra. Abortando." >&2
    exit 9
  fi
else
  echo "ERROR: no existe el directorio $PROJECT_ROOT/infra. Abortando." >&2
  exit 9
fi

# Run remove with SPREADSHEET_ID and BOT_TOKEN inline to satisfy serverless variable resolution
SPREADSHEET_ID="$SPREADSHEET_ID" BOT_TOKEN="${BOT_TOKEN-}" npx serverless remove --stage "$STAGE"

# Comprobar que stack fue eliminado
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
  echo "Advertencia: la stack $STACK_NAME todavía existe después del remove. Revisa la consola AWS CloudFormation." >&2
else
  echo "✔ Service $SERVICE has been successfully removed (stack no existe)."
fi

echo "Remove script finalizado."
