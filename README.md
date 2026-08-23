# Infra Local Example (Entorno de Desarrollo e Infraestructura)

Orquestación interna e infraestructura para proyectos y clientes con múltiples repositorios. Despliega el proxy interno Traefik, aprovisiona redes privadas aisladas (`private-network-${COMPOSE_PROJECT_NAME}`), bases de datos con persistencia en disco, servidor de WebSockets en tiempo real y herramientas de desarrollo local o producción.

---

## 🛠 Servicios y Herramientas Integradas

El stack base (núcleo) se inicia siempre por defecto, mientras que las herramientas opcionales se controlan mediante la variable `COMPOSE_PROFILES` en tu `.env` o comandos en el `Makefile`.

| Servicio / Herramienta | Perfil / Activación | URL por Defecto (Configurable en `.env`) | Credenciales por Defecto | Descripción |
| :--- | :--- | :--- | :--- | :--- |
| **Traefik Interno** | *(Core - Siempre activo)* | `https://${SUBDOMAIN_TRAEFIK:-traefik}.<dominio>/dashboard/` | `admin` / *(Definido en `.env`)* | Proxy interno conectado a `global-transit-network`. |
| **PostgreSQL (DB)** | *(Core - Siempre activo)* | `postgres:5432` *(Interno)* | `postgres` / `${POSTGRES_PASSWORD}` | Motor de base de datos relacional PostgreSQL 16. |
| **MySQL (DB)** | *(Core - Siempre activo)* | `mysql:3306` *(Interno)* | `root` / `${DB_ROOT_PASSWORD}` | Motor de base de datos relacional MySQL 8.0. |
| **MongoDB (DB)** | *(Core - Siempre activo)* | `mongodb:27017` *(Interno)* | `admin` / `${MONGO_ROOT_PASSWORD}` | Motor de base de datos NoSQL MongoDB 7.0. |
| **Redis (DB + Colas)** | *(Core - Siempre activo)* | `redis:6379` *(Interno)* | *(Pass)* `${REDIS_PASSWORD}` | Caché y Colas en memoria con persistencia AOF en disco. |
| **Centrifugo (Realtime)** | `dev`, `local`, `realtime`, `centrifugo` | `https://${SUBDOMAIN_CENTRIFUGO:-realtime}.<dominio>` | `admin` / `${CENTRIFUGO_ADMIN_PASSWORD}` | Servidor de WebSockets, SSE y canales Pub/Sub. |
| **RedisInsight** | `dev`, `local`, `tools`, `redisinsight` | `https://${SUBDOMAIN_REDISINSIGHT:-redis}.<dominio>` | *(Acceso Web)* | Panel de administración universal para Redis, Streams y Colas. |
| **Bull-Board** | `dev`, `local`, `tools`, `queues` | `https://${SUBDOMAIN_QUEUES:-queues}.<dominio>` | *(Acceso Web)* | Panel visual de monitoreo y reintento de colas Bull / BullMQ (CLI oficial). |
| **DbGate** | `dev`, `local`, `tools`, `dbgate` | `https://${SUBDOMAIN_DBGATE:-db}.<dominio>` | *(No requiere login)* | Administrador web Todo-en-Uno (MySQL, Postgres, Mongo, Redis). |
| **Mailpit** | `dev`, `local`, `tools`, `mail` | `https://${SUBDOMAIN_MAILPIT:-mail}.<dominio>` | *(No requiere login)* | Servidor SMTP y visor web de correos para pruebas. |
| **MinIO (S3)** | `dev`, `local`, `s3`, `minio` | `https://${SUBDOMAIN_MINIO_CONSOLE:-s3-console}.<dominio>` | `${MINIO_ROOT_USER}` / `${MINIO_ROOT_PASSWORD}` | Almacenamiento de objetos S3 compatible (API en `s3.<dominio>`). |
| **Evolution API** | `dev`, `local`, `whatsapp`, `evolution` | `https://${SUBDOMAIN_EVOLUTION:-whatsapp}.<dominio>` | *(API Key)* `${WA_API_KEY}` | API de integración con WhatsApp. |

---

## 🌐 Subdominios Personalizables

Todos los subdominios son configurables en tu archivo `.env`:

```bash
SUBDOMAIN_TRAEFIK=traefik
SUBDOMAIN_CENTRIFUGO=realtime
SUBDOMAIN_REDISINSIGHT=redis
SUBDOMAIN_QUEUES=queues
SUBDOMAIN_DBGATE=db
SUBDOMAIN_MAILPIT=mail
SUBDOMAIN_MINIO=s3
SUBDOMAIN_MINIO_CONSOLE=s3-console
SUBDOMAIN_EVOLUTION=whatsapp
```

---

## 🚀 Gestión Modular con `COMPOSE_PROFILES`

En tu archivo `.env` puedes definir qué módulos opcionales deseas activar:

```bash
# Todo el stack completo de desarrollo
COMPOSE_PROFILES=dev

# Solo servidor de tiempo real (WebSockets)
COMPOSE_PROFILES=realtime

# Tiempo real + Paneles de colas y datos
COMPOSE_PROFILES=realtime,redisinsight,queues

# Solo herramientas administrativas
COMPOSE_PROFILES=tools

# Solo el núcleo base (Traefik + Postgres + MySQL + Mongo + Redis con AOF)
COMPOSE_PROFILES=
```

### Comandos de conveniencia con `make`:

```bash
make up               # Inicia según COMPOSE_PROFILES en .env
make up PROFILES=s3   # Inicia módulos específicos al vuelo
make up-dev           # Inicia todo el entorno de desarrollo
make up-realtime      # Inicia núcleo + Centrifugo (WebSockets)
make up-tools         # Inicia herramientas administrativas (DbGate, Mailpit, RedisInsight, Bull-Board)
make up-core          # Inicia únicamente las bases de datos y Traefik
make up-all           # Inicia todos los servicios y perfiles
make ps               # Estado de los contenedores
make logs             # Logs en vivo
make down             # Detiene el stack
```

---

## ⚡ Conexión con Centrifugo (WebSockets & HTTP API)

- **Endpoint WebSocket para Clientes (Frontend / Apps Móviles)**:
  `wss://realtime.<dominio>/connection/websocket`
- **Endpoint HTTP API para Backends (PHP, Python, Rust, Node)**:
  - Externo: `https://realtime.<dominio>/api`
  - Interno en Docker: `http://centrifugo:8000/api`
  - Header de autenticación: `Authorization: apikey <CENTRIFUGO_API_KEY>`

---

## 💾 Importación y Respaldo de Bases de Datos

```bash
# Importar a MySQL (.sql, .sql.gz, .zip)
make import-mysql <nombre_db> <ruta_archivo>

# Importar a PostgreSQL (.sql, .sql.gz, .zip, .dump)
make import-postgres <nombre_db> <ruta_archivo>

# Importar a MongoDB (.json, .json.gz, .zip, .archive)
make import-mongo <nombre_db> <ruta_archivo> [<nombre_coleccion>]

# Ejecutar respaldo manual
make backup TYPE=daily

# Registrar cron jobs de respaldo automático
make setup-cron
```

---

## 🔒 Configuración de SSL Local (mkcert)

Para desarrollo local (`.localhost`), se utilizan certificados generados con `mkcert`:

1. **Instalar mkcert**:
   ```bash
   sudo apt update && sudo apt install libnss3-tools
   wget -O mkcert https://dl.filippo.io/mkcert/latest?for=linux/amd64
   chmod +x mkcert
   sudo mv mkcert /usr/local/bin/
   ```

2. **Generar CA y Certificados**:
   ```bash
   cd certs
   mkcert -install
   mkcert -cert-file wildcard.localhost.crt -key-file wildcard.localhost.key "*.example.localhost" "example.localhost"
   ```

3. **Reiniciar Traefik**:
   ```bash
   make restart
   ```
