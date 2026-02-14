# 🤖📊 Telegram → Google Sheets Automation

**Backend serverless que guarda automáticamente cada mensaje de un bot de Telegram en Google Sheets usando AWS Lambda.**

---

## 💡 ¿Qué hace este proyecto?

Cada vez que alguien envía un mensaje a tu bot de Telegram, este sistema:
1. ✅ Recibe el mensaje vía webhook (API Gateway)
2. ⚡ Ejecuta una función Lambda (Python 3.10)
3. 📝 Añade una fila en Google Sheets con: `username | chat_id | mensaje | timestamp`

**Sin servidor, sin mantenimiento. Todo automático.**

---

## 🏗️ Arquitectura

```
Usuario → Bot Telegram
            ↓ webhook POST
        API Gateway (AWS)
            ↓
        Lambda (Python 3.10)
            ↓
        Google Sheets API
            ↓
        📊 Google Sheet
```

**Stack tecnológico:**
- ☁️ **AWS:** Lambda, API Gateway HTTP, CloudWatch Logs
- 🐍 **Python 3.10:** handler + Google Sheets client
- 📦 **Serverless Framework:** despliegue automatizado
- 🔐 **Google Service Account:** autenticación sin usuario
- 🔧 **Bash scripts:** deploy, redeploy, remove, webhook config

---

## 📁 Estructura del Proyecto

```
automatizacion/
├── .env                      # Variables locales (SPREADSHEET_ID, BOT_TOKEN, etc.)
├── .env.example              # Plantilla con instrucciones
├── config/
│   ├── credentials.json      # Service Account JSON (no versionado)
│   └── credentials.json.example
├── infra/
│   ├── serverless.yml        # Configuración CloudFormation/Serverless
│   ├── requirements.txt      # Dependencias Python (google-api-python-client, etc.)
│   └── src/                  # Código empaquetado para deploy
├── src/
│   ├── handler.py            # Lambda entry point (recibe webhook de Telegram)
│   └── sheets.py             # Lógica append row + auth Google
├── scripts/
│   ├── deploy.sh             # Despliega stack + configura webhook automáticamente
│   ├── redeploy.sh           # Alias de deploy (idempotente)
│   ├── remove_deploy.sh      # Elimina stack y limpia S3
│   └── set_webhook.sh        # Configura webhook de Telegram con API URL
├── README.md                 # Esta documentación
└── REMOVE_DEPLOY.md          # Guía detallada de eliminación de stack
```

---

## 🚀 Inicio Rápido

### Pre-requisitos

- ✅ AWS CLI configurado (`aws configure`)
- ✅ Node.js/npm (para `npx serverless`)
- ✅ Docker (para empaquetar dependencias Python)
- ✅ Bot de Telegram creado con [@BotFather](https://t.me/botfather)
- ✅ Service Account de Google con acceso a Sheets API

### 1️⃣ Crear Service Account en Google Cloud

1. Ve a [Google Cloud Console](https://console.cloud.google.com/) → **IAM & Admin** → **Service Accounts**
2. Crea una Service Account (nombre: `telegram-sheets`)
3. Activa **Google Sheets API** en tu proyecto
4. Genera clave (JSON) y descárgala
5. Guarda el JSON en `config/credentials.json`

### 2️⃣ Crear Google Sheet y compartirlo

1. Crea una hoja nueva en [Google Sheets](https://sheets.google.com/)
2. Copia el **SPREADSHEET_ID** de la URL:
   ```
   https://docs.google.com/spreadsheets/d/ESTE_ES_EL_ID/edit
   ```
3. Comparte la hoja con el email de la Service Account (ej: `telegram-sheets@...iam.gserviceaccount.com`) con permisos de **Editor**

### 3️⃣ Crear Bot de Telegram

1. Habla con [@BotFather](https://t.me/botfather)
2. Ejecuta `/newbot` y sigue las instrucciones
3. Guarda el **token** que te da (formato: `123456:ABC-DEF...`)

### 4️⃣ Configurar variables locales

Crea o edita `.env` en la raíz del proyecto:

```bash
# Google Spreadsheet ID (obtenido de la URL de tu hoja de cálculo)
SPREADSHEET_ID="1A2B3C..."

# Token del bot de Telegram (obtenido de BotFather)
BOT_TOKEN="123456:ABC-DEF..."

# Path a credentials (dejar como está)
CREDENTIALS_PATH="config/credentials.json"
```

> 💡 **Tip:** Copia `.env.example` como base y completa los valores.

### 5️⃣ Desplegar

```bash
./scripts/deploy.sh
```

**El script automáticamente:**
- ✅ Valida que existan `BOT_TOKEN`, `SPREADSHEET_ID` y `credentials.json`
- ✅ Copia credenciales a `infra/config/` para packaging
- ✅ Instala plugin `serverless-python-requirements`
- ✅ Despliega stack a AWS (Lambda + API Gateway)
- ✅ Configura webhook de Telegram con la URL del API Gateway

**Salida esperada:**
```
✔ Service deployed to stack telegram-sheets-dev
endpoint: POST - https://abc123.execute-api.us-east-1.amazonaws.com/telegram
...
Telegram response: {"ok":true,"result":true,"description":"Webhook was set"}
```

---

## 🧪 Probar

1. Envía un mensaje a tu bot de Telegram
2. Abre tu Google Sheet → debería aparecer una nueva fila con:
   - `username` del remitente
   - `chat_id`
   - `text` del mensaje
   - `timestamp` ISO 8601

---

## 🛠️ Scripts Disponibles

| Script | Descripción |
|--------|-------------|
| `./scripts/deploy.sh` | Despliega/actualiza el stack + configura webhook automáticamente |
| `./scripts/redeploy.sh` | Alias de deploy (Serverless es idempotente) |
| `./scripts/remove_deploy.sh` | Elimina stack completo + limpia S3 bucket (vacía prefijo `serverless/` y ejecuta `sls remove`) |
| `./scripts/set_webhook.sh` | Solo configura webhook de Telegram (obtiene API URL desde CloudFormation) |

---

## 🔍 Troubleshooting

### ❌ Mensaje no aparece en Google Sheets

1. **Revisa logs de Lambda:**
   ```bash
   cd infra && npx serverless logs -f telegram --tail
   ```
2. **Verifica que la Service Account tenga permisos de Editor** en el Sheet
3. **Confirma que `config/credentials.json` sea válido**

### ❌ Webhook no recibe mensajes

```bash
# Ver estado del webhook
BOT_TOKEN="..." # tu token
curl "https://api.telegram.org/bot$BOT_TOKEN/getWebhookInfo"
```

Si `url` está vacío o apunta a otro lado:
```bash
./scripts/set_webhook.sh
```

### ❌ Error en deploy: "No file matches include / exclude patterns"

- Asegúrate de ejecutar desde la raíz del proyecto (`~/automatizacion`)
- `deploy.sh` copia archivos necesarios automáticamente

---

## 🔐 Seguridad

⚠️ **IMPORTANTE:**
- `.env` y `config/credentials.json` están en `.gitignore` → **no se suben a Git**
- Para producción: migra `BOT_TOKEN` y Service Account JSON a **AWS Secrets Manager**
- Considera validar firma de Telegram ([docs](https://core.telegram.org/bots/api#setwebhook))

---

## 🗑️ Eliminar Stack

```bash
./scripts/remove_deploy.sh
```

El script:
1. Lista objetos en el bucket S3 de deployment
2. Pide confirmación antes de borrar el prefijo `serverless/`
3. Elimina versiones si el bucket tiene versionado habilitado
4. Ejecuta `npx serverless remove --stage dev`
5. Verifica que la stack fue eliminada de CloudFormation

> 📖 Más detalles en [REMOVE_DEPLOY.md](./REMOVE_DEPLOY.md)

---

## 📦 Dependencias

**Python (instaladas automáticamente por Serverless):**
- `google-api-python-client` - Cliente Google Sheets API
- `google-auth` - Autenticación Service Account
- `google-auth-httplib2` - HTTP transport

**Node.js (dev):**
- `serverless-python-requirements` - Empaqueta deps Python con Docker

---

## 🚀 Mejoras Futuras

- [ ] Migrar credenciales a AWS Secrets Manager
- [ ] Validar firma de Telegram en el webhook
- [ ] Rate limiting para evitar spam
- [ ] Soporte para comandos del bot (`/start`, `/help`)
- [ ] Enviar respuestas desde Lambda al usuario (API de Telegram)
- [ ] Logs estructurados con niveles (INFO, ERROR)

---

## 📄 Licencia

Proyecto de ejemplo sin licencia específica. Úsalo y modifícalo libremente.

---

**Desarrollado con ❤️ usando AWS Serverless + Python + Google Sheets API**

- [ ] Migrar credenciales a AWS Secrets Manager
- [ ] Agregar validación de webhook signature de Telegram
- [ ] Implementar rate limiting
- [ ] Agregar soporte para otros tipos de mensajes (fotos, documentos)
- [ ] Implementar retry logic con DLQ
- [ ] Agregar métricas y alertas con CloudWatch

## 📄 Licencia

MIT

## 👤 Autor

Backend Engineer - AWS Serverless Specialist
