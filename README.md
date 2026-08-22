# Infra Local Example (Entorno de Desarrollo)

Internal orchestration and infrastructure for projects with multiple repositories. Deploys the internal Traefik router, provisions isolated private networks, y sirve como el entorno base de desarrollo local para Example.

## 🛠 Herramientas de Desarrollo Integradas

Este entorno (`--profile local`) levanta automáticamente un conjunto de herramientas modernas para facilitar el desarrollo local:

| Herramienta | URL | Usuario por defecto | Contraseña por defecto | Descripción |
| :--- | :--- | :--- | :--- | :--- |
| **DbGate** | `https://db.example.localhost` | *(No requiere login)* | *(No requiere login)* | Gestor Todo-en-Uno. Ya configurado para conectar a MySQL, MongoDB y Redis local. |
| **MySQL (DB)** | *(Interno en DbGate)* | `root` | `root` | Motor de base de datos relacional (Puerto interno 3306). |
| **MongoDB (DB)**| *(Interno en DbGate)* | `root` | `root` | Motor de base de datos NoSQL (Puerto interno 27017). |
| **Redis (DB)** | *(Interno en DbGate)* | *(No usa)* | `root` | Caché y Key-Value store (Puerto interno 6379). |
| **Mailpit** | `https://mail.example.localhost` | *(No requiere login)* | *(No requiere login)* | Servidor SMTP para pruebas e interfaz web de correos. |
| **MinIO (S3)** | `https://s3-console.example.localhost` | `admin` | `password123` | Almacenamiento S3. (La API es `https://s3.example.localhost`). |
| **Evolution API** | `https://whatsapp.example.localhost` | *(Auth by API Key)* | `${WA_API_KEY}` | API de WhatsApp. (La API Key se configura en tu `.env`). |
| **Traefik (Dominio)** | `https://traefik.example.localhost/dashboard/` | `admin` | `admin123` | Dashboard del proxy Traefik que enruta este dominio específico. |

*(Nota: En entornos de producción como alpha/beta/prod, no se despliegan estas herramientas por motivos de seguridad).*

## 🔒 Configuración de SSL Local (mkcert)

Para evitar las advertencias de seguridad del navegador ("La conexión no es privada"), utilizamos certificados locales generados con `mkcert`. El proxy inverso Traefik está configurado para leer un **Certificado Comodín** (*Wildcard Certificate*) automáticamente.

### Pasos para generar el certificado de forma local:

1. **Instalar mkcert** (en Ubuntu/Debian):
   ```bash
   sudo apt update && sudo apt install libnss3-tools
   wget -O mkcert https://dl.filippo.io/mkcert/latest?for=linux/amd64
   chmod +x mkcert
   sudo mv mkcert /usr/local/bin/
   ```

2. **Generar la Autoridad Local y los Certificados**:
   ```bash
   # Entra a la carpeta de certificados de este repositorio
   cd certs

   # Instala la CA en tu sistema (solo se hace una vez)
   mkcert -install

   # Genera el certificado comodín para todo *.example.localhost
   mkcert -cert-file wildcard.localhost.crt -key-file wildcard.localhost.key "*.example.localhost" "example.localhost"
   ```

3. **Reiniciar Traefik** para que aplique los cambios:
   ```bash
   cd ..
   docker compose restart traefik-internal
   ```
¡Listo! Tus navegadores confiarán plenamente en todos tus dominios de desarrollo `.localhost`.
