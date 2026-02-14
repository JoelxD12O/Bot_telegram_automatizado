# Eliminación (remove) del despliegue de Serverless

## Explicación de lo que tenemos

- Proyecto Serverless llamado `telegram-sheets` desplegado en la cuenta AWS `176520790370`.
- Stack CloudFormation: `telegram-sheets-dev` (región `us-east-1`).
- Bucket de deployment creado por Serverless: `telegram-sheets-dev-serverlessdeploymentbucket-ayjvusv7qii7`.
- Código y artefactos del servicio están en `infra/` y `infra/src`.
- Variable necesaria en `serverless.yml`: `SPREADSHEET_ID` (se resuelve desde variables de entorno).
- Credenciales Google en `config/credentials.json` y Bot Token de Telegram (no en ficheros por seguridad).

## Objetivo

Eliminar completamente los recursos creados por Serverless (Lambda, API Gateway, roles, etc.) usando `npx serverless remove --stage dev` y manejar los problemas comunes que aparecen durante la eliminación.

## Resumen de la secuencia realizada

1. Intento de `serverless remove` falló por variable faltante:

```bash
npx serverless remove --stage dev
```

Error esperado si `SPREADSHEET_ID` no está exportado:

```
Cannot resolve serverless.yml: Variables resolution errored with:
  - Cannot resolve variable at "provider.environment.SPREADSHEET_ID": Value not found at "env" source
```

Acción: exportar la variable en la sesión actual o pasarla inline.

```bash
export SPREADSHEET_ID="15bxI2lR9gWNOJ4s6xAOGKxzMyW7JOJ1xzegGaABGyVw"
# o (sin exportar la variable globalmente)
SPREADSHEET_ID="15bxI2lR9gWNOJ4s6xAOGKxzMyW7JOJ1xzegGaABGyVw" npx serverless remove --stage dev
```

2. Ejecutar `remove` produjo fallo porque el bucket de deployment no estaba vacío:

Mensaje de error mostrado:

```
DELETE_FAILED: ServerlessDeploymentBucket (AWS::S3::Bucket)
Resource handler returned message: "The bucket you tried to delete is not empty (...)
```

Significado: CloudFormation no puede eliminar un bucket S3 si contiene objetos.

3. Confirmar el contenido del prefijo `serverless/` en el bucket:

```bash
BUCKET=telegram-sheets-dev-serverlessdeploymentbucket-ayjvusv7qii7
aws s3 ls "s3://$BUCKET/serverless/" --recursive
```

Salida ejemplo (si hay artifact):

```
2026-02-13 13:38:31   16858082 serverless/.serverless/telegram-sheets.zip
```

4. Borrar recursivamente solo el prefijo `serverless/` (no el bucket completo):

```bash
aws s3 rm "s3://$BUCKET/serverless/" --recursive
```

Salida esperada (cada objeto borrado):

```
delete: s3://<bucket>/serverless/.serverless/telegram-sheets.zip
```

5. Verificar que el prefijo quedó vacío:

```bash
aws s3 ls "s3://$BUCKET/serverless/" --recursive || echo "Prefijo serverless/ vacío"
```

Si el bucket usa versionado (opcional):

```bash
aws s3api get-bucket-versioning --bucket "$BUCKET"
```

Si devuelve `Status: Enabled`, hay que eliminar versiones y delete-markers con `list-object-versions` y `delete-objects`. Ejemplo seguro con payload:

```bash
aws s3api list-object-versions --bucket "$BUCKET" --prefix serverless/ --output json > /tmp/versions.json

python3 - <<'PY'
import json
j=json.load(open('/tmp/versions.json'))
objs=[]
for v in j.get('Versions',[]):
    objs.append({'Key':v['Key'],'VersionId':v['VersionId']})
for dm in j.get('DeleteMarkers',[]):
    objs.append({'Key':dm['Key'],'VersionId':dm['VersionId']})
if objs:
    open('/tmp/delete_payload.json','w').write(json.dumps({'Objects':objs,'Quiet':False}))
    print('Payload preparado en /tmp/delete_payload.json')
else:
    print('No hay versiones/delete-markers para prefix serverless/')
PY

aws s3api delete-objects --bucket "$BUCKET" --delete file:///tmp/delete_payload.json
```

6. Reintentar eliminar el stack con `serverless remove` (ya con prefijo vacío):

```bash
cd ~/automatizacion/infra
SPREADSHEET_ID="15bxI2lR9gWNOJ4s6xAOGKxzMyW7JOJ1xzegGaABGyVw" npx serverless remove --stage dev
```

Salida esperada al final:

```
✔ Service telegram-sheets has been successfully removed (8s)
```

7. Comprobar que el stack ya no existe:

```bash
aws cloudformation describe-stacks --stack-name telegram-sheets-dev || echo "Stack no encontrado (posible eliminación exitosa)"
```

Salida cuando el stack no existe:

```
An error occurred (ValidationError) when calling the DescribeStacks operation: Stack with id telegram-sheets-dev does not exist
Stack no encontrado (posible eliminación exitosa)
```

## Posibles resultados y su significado

- `Cannot resolve variable... SPREADSHEET_ID`: falta exportar la variable en entorno. Solución: exportarla o pasarla inline.
- `DELETE_FAILED: ServerlessDeploymentBucket`: el bucket contiene objetos; vacía el prefijo `serverless/` y reintenta.
- `403 Forbidden` en `curl` a `https://<bucket>.s3.amazonaws.com`: salida normal para peticiones anónimas; no indica problema si el bucket existe.
- `Stack no encontrado (DescribeStacks)`: indica que la pila fue eliminada correctamente.

## Cómo volver a desplegar (después de remove)

1. Asegúrate de tener:
   - `config/credentials.json` con la Service Account de Google
   - `SPREADSHEET_ID` exportado
   - Credenciales AWS configuradas

2. Ejecuta deploy:

```bash
cd ~/automatizacion/infra
SPREADSHEET_ID="15bxI2lR9gWNOJ4s6xAOGKxzMyW7JOJ1xzegGaABGyVw" npx serverless deploy --verbose
```

3. Configura el webhook de Telegram con la URL resultante (si cambia):

```bash
BOT_TOKEN="<tu_bot_token>"
API_URL="https://<endpoint_obtenido>"
curl -X POST "https://api.telegram.org/bot$BOT_TOKEN/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"$API_URL/telegram\"}"
```

## Notas de seguridad y buenas prácticas

- No subas `config/credentials.json` ni `BOT_TOKEN` a repositorios públicos.
- Para producción, mueve credenciales a AWS Secrets Manager y referencia en `serverless.yml`.
- Evita borrar el bucket S3 completo si contiene artifacts de otros servicios.

## Ubicación del script de despliegue del proyecto

- Script usado: `scripts/deploy.sh`
- Configuración Serverless: `infra/serverless.yml`

Fin del documento.
