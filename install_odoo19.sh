#!/bin/bash
# Script de instalación de Odoo 17 Community en Ubuntu Server
# Ejecutar con privilegios de sudo: sudo bash install_odoo.sh

set -e

# --- VARIABLES DE CONFIGURACIÓN ---
ODOO_USER="odoo"
ODOO_HOME="/opt/$ODOO_USER"
ODOO_VERSION="17.0"
ODOO_PORT="8069"
ODOO_CONF="/etc/odoo.conf"
# ----------------------------------

echo "=== 1. Actualizando paquetes del sistema ==="
sudo apt update && sudo apt upgrade -y

echo "=== 2. Instalando PostgreSQL y dependencias ==="
sudo apt install -y postgresql postgresql-contrib python3-pip python3-dev \
  python3-venv build-essential libxml2-dev libxslt1-dev zlib1g-dev \
  libsasl2-dev libldap2-dev libjpeg-dev libpq-dev git wget

echo "=== 3. Creando el usuario del sistema y la base de datos ==="
# Crear usuario del sistema si no existe
if ! id -u "$ODOO_USER" >/dev/null 2>&1; then
    sudo useradd -m -d $ODOO_HOME -U -r -s /bin/bash $ODOO_USER
fi

# Crear usuario en PostgreSQL con el mismo nombre
sudo -u postgres createuser -s $ODOO_USER 2>/dev/null || true

echo "=== 4. Clonando Odoo $ODOO_VERSION ==="
if [ ! -d "$ODOO_HOME/odoo" ]; then
    sudo -u $ODOO_USER git clone --depth 1 --branch $ODOO_VERSION https://www.github.com/odoo/odoo $ODOO_HOME/odoo
fi

echo "=== 5. Creando entorno virtual e instalando requisitos de Python ==="
sudo -u $ODOO_USER python3 -m venv $ODOO_HOME/venv
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install --upgrade pip
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install -r $ODOO_HOME/odoo/requirements.txt

echo "=== 6. Instalando wkhtmltopdf (para exportar reportes en PDF) ==="
cd /tmp
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb -O wkhtmltox.deb
sudo apt install -y ./wkhtmltox.deb
rm wkhtmltox.deb

echo "=== 7. Creando directorio de módulos personalizados y logs ==="
sudo mkdir -p $ODOO_HOME/custom-addons
sudo mkdir -p /var/log/odoo
sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME/custom-addons
sudo chown -R $ODOO_USER:$ODOO_USER /var/log/odoo

echo "=== 8. Generando archivo de configuración ==="
# Generar una contraseña aleatoria para la administración de bases de datos
ADMIN_PASSWD=$(openssl rand -hex 12)

sudo bash -c "cat <<EOF > $ODOO_CONF
[options]
admin_passwd = $ADMIN_PASSWD
db_host = False
db_port = False
db_user = $ODOO_USER
db_password = False
xmlrpc_port = $ODOO_PORT
logfile = /var/log/odoo/odoo.log
addons_path = $ODOO_HOME/odoo/addons,$ODOO_HOME/custom-addons
EOF"

sudo chown $ODOO_USER:$ODOO_USER $ODOO_CONF
sudo chmod 640 $ODOO_CONF

echo "=== 9. Creando servicio systemd para Odoo ==="
sudo bash -c "cat <<EOF > /etc/systemd/system/odoo.service
[Unit]
Description=Odoo $ODOO_VERSION
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo/odoo-bin -c $ODOO_CONF
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF"

echo "=== 10. Iniciando el servicio ==="
sudo systemctl daemon-reload
sudo systemctl enable --now odoo

echo ""
echo "============================================================"
echo " ¡Instalación completada con éxito!"
echo " Contraseña maestra de BD (admin_passwd): $ADMIN_PASSWD"
echo " Guarda esta contraseña en un lugar seguro."
echo ""
echo " Accede desde tu navegador en: http://<IP_DE_TU_SERVIDOR>:$ODOO_PORT"
echo "============================================================"