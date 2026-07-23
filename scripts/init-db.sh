#!/bin/bash
set -euo pipefail

echo "🐳 Iniciando creación de bases de datos y usuarios desde .env..."

i=1
while true; do
  # Generar dinámicamente los nombres de las variables
  db_name_var="MYSQL_DB_${i}_NAME"
  db_user_var="MYSQL_DB_${i}_USER"
  db_pass_var="MYSQL_DB_${i}_PASS"

  # Si la variable de nombre no está definida, rompemos el bucle
  if [ -z "${!db_name_var:-}" ]; then
    break
  fi

  db_name="${!db_name_var}"
  db_user="${!db_user_var}"
  db_pass="${!db_pass_var}"

  echo "🔑 Creando base de datos '${db_name}' y asignando al usuario '${db_user}'..."

  # Ejecutar comandos SQL en MySQL
  mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "
    CREATE DATABASE IF NOT EXISTS \`${db_name}\`;
    CREATE USER IF NOT EXISTS '${db_user}'@'%' IDENTIFIED BY '${db_pass}';
    GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'%';
  "

  i=$((i + 1))
done

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;"
echo "✅ Inicialización dinámica completada con éxito."
