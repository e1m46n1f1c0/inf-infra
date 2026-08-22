#!/bin/bash
# =================================================================
# DATABASE BACKUP SCRIPT FOR EXAMPLE INFRASTRUCTURE
# =================================================================
set -uo pipefail

# Obtener rutas absolutas basadas en la ubicación del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Cargar variables de entorno del .env
if [ -f "$PROJECT_DIR/.env" ]; then
    set -o allexport
    source "$PROJECT_DIR/.env"
    set +o allexport
fi

# Variables de retención configurables con valores por defecto
RETENTION_HOURLY_HOURS="${RETENTION_HOURLY_HOURS:-48}"
RETENTION_DAILY_DAYS="${RETENTION_DAILY_DAYS:-30}"
RETENTION_WEEKLY_WEEKS="${RETENTION_WEEKLY_WEEKS:-8}"
RETENTION_MONTHLY_MONTHS="${RETENTION_MONTHLY_MONTHS:-12}"

# Parámetros del backup
TYPE="${1:-hourly}" # Por defecto hourly
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
ISO_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BACKUP_DIR="$PROJECT_DIR/backups/$TYPE"
TEMP_DIR="$PROJECT_DIR/backups/temp_$TIMESTAMP"

# Determinar subcarpeta basada en el tipo de intervalo
case "$TYPE" in
    hourly)
        SUB_FOLDER="$(date +%H)0000"
        ;;
    daily|weekly)
        SUB_FOLDER="$(date +%Y-%m-%d)"
        ;;
    monthly)
        SUB_FOLDER="$(date +%Y-%m)"
        ;;
    *)
        SUB_FOLDER="$TIMESTAMP"
        ;;
esac

# Ruta remota (con prefijo opcional SPACES_ROOT)
if [ -n "${SPACES_ROOT:-}" ]; then
    # Limpiar slashes iniciales o finales
    SPACES_ROOT_CLEANED=$(echo "$SPACES_ROOT" | sed -e 's/^\///' -e 's/\/$//')
    REMOTE_PATH="${SPACES_ROOT_CLEANED}/${TYPE}/${SUB_FOLDER}"
    RETENTION_PREFIX="${SPACES_ROOT_CLEANED}/${TYPE}/"
else
    REMOTE_PATH="${TYPE}/${SUB_FOLDER}"
    RETENTION_PREFIX="${TYPE}/"
fi

# Crear directorios de trabajo
mkdir -p "$BACKUP_DIR"
mkdir -p "$TEMP_DIR"

# Nombres de contenedores y credenciales
MYSQL_CONTAINER="mysql-${COMPOSE_PROJECT_NAME:-example}"
MONGO_CONTAINER="mongodb-${COMPOSE_PROJECT_NAME:-example}"
MYSQL_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-root}"
MONGO_ROOT_USER="${MONGO_ROOT_USER:-admin}"
MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-root}"

# Listado de bases de datos procesadas para el reporte
MYSQL_DBS_BACKED_UP=""
MONGO_DBS_BACKED_UP=""
ERROR_MSG=""

# Función para enviar notificaciones a Discord/Slack
send_notification() {
    local status="$1"
    local detail="$2"
    
    if [ -z "${NOTIFICATION_WEBHOOK_URL:-}" ]; then
        echo "ℹ️ No se configuró NOTIFICATION_WEBHOOK_URL. Omitiendo notificación."
        return 0
    fi

    local color=3066993 # Verde para Success
    local title="✅ Backup Completado"
    if [ "$status" = "error" ]; then
        color=15158332 # Rojo para Error
        title="❌ Fallo en Backup"
    fi

    local payload
    payload=$(cat <<EOF
{
  "content": null,
  "embeds": [
    {
      "title": "$title",
      "color": $color,
      "fields": [
        {"name": "Entorno", "value": "${COMPOSE_PROJECT_NAME:-example} (local)", "inline": true},
        {"name": "Tipo", "value": "$TYPE", "inline": true},
        {"name": "Fecha", "value": "$TIMESTAMP", "inline": true},
        {"name": "Detalles", "value": "$detail", "inline": false}
      ],
      "timestamp": "$ISO_TIME"
    }
  ]
}
EOF
)

    if [[ "$NOTIFICATION_WEBHOOK_URL" == *"your_webhook_url"* ]]; then
        echo "⚠️ Advertencia: NOTIFICATION_WEBHOOK_URL contiene el marcador de posición por defecto. Por favor, edita tu archivo .env con la URL real de Discord."
        return 0
    fi

    echo "Sending notification..."
    local response
    response=$(curl -s -w "\n%{http_code}" -H "Content-Type: application/json" -X POST -d "$payload" "$NOTIFICATION_WEBHOOK_URL")
    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
        echo "⚠️ Error al enviar la notificación. Código HTTP: $http_code"
        echo "Respuesta de Discord: $body"
    else
        echo "✅ Notificación enviada con éxito."
    fi
}

# =================================================================
# 1. RESPALDO MYSQL (POR BASE DE DATOS)
# =================================================================
echo "🐳 Iniciando respaldos de MySQL..."
if ! docker ps -q -f name="^${MYSQL_CONTAINER}$" > /dev/null; then
    echo "❌ Error: El contenedor MySQL ($MYSQL_CONTAINER) no está en ejecución."
    ERROR_MSG="El contenedor MySQL ($MYSQL_CONTAINER) no está en ejecución."
else
    # Obtener lista de bases de datos
    databases=$(docker exec "$MYSQL_CONTAINER" mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES;" -s --skip-column-names 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$databases" ]; then
        echo "❌ Error: No se pudo conectar a MySQL o no hay bases de datos."
        ERROR_MSG="No se pudo obtener las bases de datos de MySQL."
    else
        for db in $databases; do
            # Omitir bases de datos del sistema
            if [ "$db" = "information_schema" ] || [ "$db" = "performance_schema" ] || [ "$db" = "sys" ] || [ "$db" = "mysql" ]; then
                continue
            fi
            
            echo "  📦 Respaldando base de datos MySQL: $db"
            sql_file="mysql_db_${db}_${TIMESTAMP}.sql"
            tar_file="mysql_db_${db}_${TIMESTAMP}.tar.gz"
            
            # Dump a archivo temporal en host
            if docker exec -i "$MYSQL_CONTAINER" mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" "$db" > "$TEMP_DIR/$sql_file" 2>/dev/null; then
                # Comprimir
                tar -czf "$BACKUP_DIR/$tar_file" -C "$TEMP_DIR" "$sql_file"
                rm -f "$TEMP_DIR/$sql_file"
                MYSQL_DBS_BACKED_UP="$MYSQL_DBS_BACKED_UP\n- $db ($(du -sh "$BACKUP_DIR/$tar_file" | cut -f1))"
            else
                echo "  ❌ Falló el respaldo de $db"
                ERROR_MSG="$ERROR_MSG\nFalló dump de base de datos MySQL '$db'."
            fi
        done
    fi
fi

# =================================================================
# 2. RESPALDO MONGODB (POR BASE DE DATOS)
# =================================================================
echo "🐳 Iniciando respaldos de MongoDB..."
if ! docker ps -q -f name="^${MONGO_CONTAINER}$" > /dev/null; then
    echo "❌ Error: El contenedor MongoDB ($MONGO_CONTAINER) no está en ejecución."
    ERROR_MSG="${ERROR_MSG:+$ERROR_MSG\n}El contenedor MongoDB ($MONGO_CONTAINER) no está en ejecución."
else
    # Limpiar posibles dumps previos en el contenedor y ejecutar mongodump
    docker exec "$MONGO_CONTAINER" rm -rf /tmp/mongodump 2>/dev/null || true
    if docker exec "$MONGO_CONTAINER" mongodump --uri="mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASSWORD}@localhost:27017/?authSource=admin" --out=/tmp/mongodump > /dev/null 2>&1; then
        # Copiar estructura al host
        mkdir -p "$TEMP_DIR/mongo_dumps"
        docker cp "$MONGO_CONTAINER:/tmp/mongodump/." "$TEMP_DIR/mongo_dumps/"
        docker exec "$MONGO_CONTAINER" rm -rf /tmp/mongodump
        
        # Procesar carpetas de bases de datos
        if [ -d "$TEMP_DIR/mongo_dumps" ]; then
            for db_dir in "$TEMP_DIR/mongo_dumps"/*; do
                if [ -d "$db_dir" ]; then
                    db_name=$(basename "$db_dir")
                    # Omitir bases del sistema de MongoDB
                    if [ "$db_name" = "admin" ] || [ "$db_name" = "config" ] || [ "$db_name" = "local" ]; then
                        continue
                    fi
                    
                    echo "  📦 Respaldando base de datos MongoDB: $db_name"
                    tar_file="mongo_db_${db_name}_${TIMESTAMP}.tar.gz"
                    
                    # Comprimir la carpeta de la base de datos
                    tar -czf "$BACKUP_DIR/$tar_file" -C "$TEMP_DIR/mongo_dumps" "$db_name"
                    MONGO_DBS_BACKED_UP="$MONGO_DBS_BACKED_UP\n- $db_name ($(du -sh "$BACKUP_DIR/$tar_file" | cut -f1))"
                fi
            done
        fi
    else
        echo "  ❌ Falló el dump general de MongoDB"
        ERROR_MSG="${ERROR_MSG:+$ERROR_MSG\n}Falló dump de MongoDB."
    fi
fi

# =================================================================
# 3. CARGA A DIGITALOCEAN SPACES
# =================================================================
SPACES_CONFIGURED=true
for var in SPACES_KEY SPACES_SECRET SPACES_BUCKET SPACES_ENDPOINT SPACES_REGION; do
    if [ -z "${!var:-}" ]; then
        SPACES_CONFIGURED=false
    fi
done

UPLOAD_SUCCESS=true
if [ "$SPACES_CONFIGURED" = "true" ]; then
    echo "☁️ Subiendo respaldos a DigitalOcean Spaces..."
    
    # Listar archivos generados
    files_to_upload=$(find "$BACKUP_DIR" -maxdepth 1 -name "*.tar.gz")
    
    if [ -z "$files_to_upload" ]; then
        echo "⚠️ No hay archivos de backup para subir."
        UPLOAD_SUCCESS=false
    else
        for file in $files_to_upload; do
            filename=$(basename "$file")
            
            echo "  📤 Subiendo: $filename a $TYPE/$SUB_FOLDER/..."
            
            # Ejecutar aws-cli mediante docker
            if ! docker run --rm \
                -e AWS_ACCESS_KEY_ID="$SPACES_KEY" \
                -e AWS_SECRET_ACCESS_KEY="$SPACES_SECRET" \
                -e AWS_DEFAULT_REGION="$SPACES_REGION" \
                -v "$BACKUP_DIR:/backups" \
                amazon/aws-cli s3 cp "/backups/$filename" "s3://$SPACES_BUCKET/$REMOTE_PATH/$filename" --endpoint-url "$SPACES_ENDPOINT" > /dev/null 2>&1; then
                echo "  ❌ Error al subir $filename"
                ERROR_MSG="${ERROR_MSG:+$ERROR_MSG\n}Error al subir $filename a Spaces."
                UPLOAD_SUCCESS=false
            fi
        done
    fi
else
    echo "⚠️ DigitalOcean Spaces no está configurado completamente en .env. Omitiendo carga remota."
    ERROR_MSG="${ERROR_MSG:+$ERROR_MSG\n}Carga a Spaces omitida (falta configuración en .env)."
    UPLOAD_SUCCESS=false
fi

# =================================================================
# 4. POLÍTICA DE RETENCIÓN EN DIGITALOCEAN SPACES
# =================================================================
if [ "$SPACES_CONFIGURED" = "true" ] && [ "$UPLOAD_SUCCESS" = "true" ]; then
    echo "🧹 Aplicando política de retención en DigitalOcean Spaces..."
    
    # Calcular fecha límite según tipo
    cutoff_seconds=0
    case "$TYPE" in
        hourly) cutoff_seconds=$((RETENTION_HOURLY_HOURS * 3600)) ;;
        daily) cutoff_seconds=$((RETENTION_DAILY_DAYS * 86400)) ;;
        weekly) cutoff_seconds=$((RETENTION_WEEKLY_WEEKS * 7 * 86400)) ;;
        monthly) cutoff_seconds=$((RETENTION_MONTHLY_MONTHS * 30 * 86400)) ;;
    esac
    
    cutoff_date=$(date -u -d "@$(($(date +%s) - cutoff_seconds))" +%Y-%m-%dT%H:%M:%SZ)
    echo "  Cutoff date: $cutoff_date"

    # Listar objetos remotos con prefijo $RETENTION_PREFIX
    remote_keys=$(docker run --rm \
        -e AWS_ACCESS_KEY_ID="$SPACES_KEY" \
        -e AWS_SECRET_ACCESS_KEY="$SPACES_SECRET" \
        amazon/aws-cli s3api list-objects-v2 \
        --bucket "$SPACES_BUCKET" \
        --prefix "$RETENTION_PREFIX" \
        --endpoint-url "$SPACES_ENDPOINT" \
        --query "Contents[?LastModified<'$cutoff_date'].Key" \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$remote_keys" ] && [ "$remote_keys" != "None" ]; then
        for key in $remote_keys; do
            # Validar que no sea vacío ni nulo
            if [ -n "$key" ] && [ "$key" != "None" ]; then
                echo "  🗑️ Eliminando remoto expirado: $key"
                docker run --rm \
                    -e AWS_ACCESS_KEY_ID="$SPACES_KEY" \
                    -e AWS_SECRET_ACCESS_KEY="$SPACES_SECRET" \
                    amazon/aws-cli s3api delete-object \
                    --bucket "$SPACES_BUCKET" \
                    --key "$key" \
                    --endpoint-url "$SPACES_ENDPOINT" > /dev/null 2>&1 || echo "  ⚠️ Error al eliminar $key"
            fi
        done
    fi
fi

# =================================================================
# 5. INFORME / NOTIFICACIÓN Y LIMPIEZA
# =================================================================
# Formatear el reporte de detalles
REPORT=""
if [ -n "$MYSQL_DBS_BACKED_UP" ]; then
    REPORT="$REPORT**MySQL:**$MYSQL_DBS_BACKED_UP\n"
fi
if [ -n "$MONGO_DBS_BACKED_UP" ]; then
    REPORT="$REPORT**MongoDB:**$MONGO_DBS_BACKED_UP\n"
fi

if [ -n "$ERROR_MSG" ]; then
    if [ "$UPLOAD_SUCCESS" = "true" ] && [ -n "$REPORT" ]; then
        # Hubo advertencias o fallos menores pero se respaldó parte y se subió
        send_notification "success" "$REPORT\n⚠️ **Notas:** $ERROR_MSG"
    else
        # Falló completamente o no se subió
        send_notification "error" "❌ **Fallo de Backup:** $ERROR_MSG\n\n$REPORT"
    fi
else
    send_notification "success" "$REPORT"
fi

# Limpieza absoluta local
echo "🧹 Eliminando carpeta temporal y local backups/..."
rm -rf "$PROJECT_DIR/backups"

echo "✅ Proceso de backup finalizado."
