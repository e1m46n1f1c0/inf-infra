#!/bin/bash
set -e

# Cargar variables del .env si existe
if [ -f .env ]; then
    set -o allexport
    source .env
    set +o allexport
fi

TYPE="$1"
DB_NAME="$2"
FILE_PATH="$3"
COL_NAME="$4"

if [ -z "$TYPE" ] || [ -z "$DB_NAME" ] || [ -z "$FILE_PATH" ]; then
    echo "Uso: $0 <mysql|mongo> <nombre_db> <ruta_archivo> [<coleccion_para_json>]"
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "❌ Error: El archivo '$FILE_PATH' no existe."
    exit 1
fi

MYSQL_CONTAINER="mysql-${COMPOSE_PROJECT_NAME:-example}"
MONGO_CONTAINER="mongodb-${COMPOSE_PROJECT_NAME:-example}"
MYSQL_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-root}"
MONGO_ROOT_USER="${MONGO_ROOT_USER:-admin}"
MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-root}"

if [ "$TYPE" = "mysql" ]; then
    echo "⏳ Importando a MySQL ($DB_NAME) desde '$FILE_PATH'..."
    if [[ "$FILE_PATH" == *.gz ]]; then
        gunzip -c "$FILE_PATH" | docker exec -i "$MYSQL_CONTAINER" mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$DB_NAME"
    elif [[ "$FILE_PATH" == *.zip ]]; then
        unzip -p "$FILE_PATH" | docker exec -i "$MYSQL_CONTAINER" mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$DB_NAME"
    else
        docker exec -i "$MYSQL_CONTAINER" mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$DB_NAME" < "$FILE_PATH"
    fi
    echo "✅ Importación MySQL completada con éxito."

elif [ "$TYPE" = "mongo" ]; then
    echo "⏳ Importando a MongoDB ($DB_NAME) desde '$FILE_PATH'..."
    
    # Traducir extensión del archivo
    if [[ "$FILE_PATH" == *.json ]] || [[ "$FILE_PATH" == *.json.gz ]]; then
        if [ -z "$COL_NAME" ]; then
            echo "❌ Error: Debes especificar el nombre de la colección para archivos JSON."
            echo "Ejemplo: make import-mongo $DB_NAME $FILE_PATH mi_coleccion"
            exit 1
        fi
        
        if [[ "$FILE_PATH" == *.gz ]]; then
            gunzip -c "$FILE_PATH" | docker exec -i "$MONGO_CONTAINER" mongoimport --uri="mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASSWORD}@localhost:27017/${DB_NAME}?authSource=admin" --collection="$COL_NAME" --drop
        else
            docker exec -i "$MONGO_CONTAINER" mongoimport --uri="mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASSWORD}@localhost:27017/${DB_NAME}?authSource=admin" --collection="$COL_NAME" --drop < "$FILE_PATH"
        fi
        
    elif [[ "$FILE_PATH" == *.zip ]] || [[ "$FILE_PATH" == *.archive ]] || [[ "$FILE_PATH" == *.tar.gz ]]; then
        # Copiar el archivo al contenedor para poder operar con herramientas nativas de restauración
        TEMP_FILE="/tmp/mongo_restore_$(date +%s)"
        docker cp "$FILE_PATH" "${MONGO_CONTAINER}:${TEMP_FILE}"
        
        # Intentar restaurar como archivo mongorestore primero (archive)
        echo "  📦 Intentando restaurar como archivo de volcado (mongorestore --archive)..."
        if docker exec -i "$MONGO_CONTAINER" mongorestore --uri="mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASSWORD}@localhost:27017/${DB_NAME}?authSource=admin" --archive="${TEMP_FILE}" --nsInclude="*" 2>/dev/null; then
            echo "  ✅ Restauración desde archivo completada."
        else
            # Si falla, verificar si es un ZIP con un directorio de BSONs
            echo "  📂 No se pudo restaurar como archivo directo. Intentando descomprimir y restaurar directorio..."
            TEMP_DIR="/tmp/mongo_restore_dir_$(date +%s)"
            docker exec -i "$MONGO_CONTAINER" sh -c "
                mkdir -p ${TEMP_DIR} && \
                unzip -q -d ${TEMP_DIR} ${TEMP_FILE} 2>/dev/null || tar -xf ${TEMP_FILE} -C ${TEMP_DIR} 2>/dev/null || true
            "
            
            # Restaurar el directorio descomprimido
            docker exec -i "$MONGO_CONTAINER" mongorestore --uri="mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASSWORD}@localhost:27017/${DB_NAME}?authSource=admin" --dir="${TEMP_DIR}"
            
            # Limpiar directorio temporal
            docker exec -i "$MONGO_CONTAINER" rm -rf "${TEMP_DIR}"
            echo "  ✅ Restauración desde directorio completada."
        fi
        
        # Limpiar archivo temporal
        docker exec -i "$MONGO_CONTAINER" rm -f "${TEMP_FILE}"
    else
        echo "❌ Error: Formato de archivo no soportado para MongoDB (.json, .json.gz, .zip, .archive)."
        exit 1
    fi
    echo "✅ Importación MongoDB completada con éxito."
else
    echo "❌ Error: Tipo de base de datos desconocido '$TYPE'."
    exit 1
fi
