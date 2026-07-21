#!/bin/bash
# Script de instalación de Odoo 19.0 Community en Ubuntu Server 22.04 / 24.04
# Ejecutar con privilegios de sudo: sudo bash install_odoo19.sh

set -e

# --- VARIABLES DE CONFIGURACIÓN ---
ODOO_USER="odoo"
ODOO_HOME="/opt/$ODOO_USER"
ODOO_VERSION="19.0"
ODOO_PORT="8069"
ODOO_CONF="/etc/odoo.conf"
# ----------------------------------

echo "=== 1. Actualizando repositorio y paquetes del sistema ==="
sudo apt update && sudo apt upgrade -y

echo "=== 2. Instalando Python 3.12, PostgreSQL y herramientas de desarrollo ==="
# Instalamos Python 3.12, paquetes de C/Rust para evitar fallos de librerías y dependencias clave
sudo apt install -y postgresql postgresql-contrib python3.12 python3.12-venv python3.12-dev \
  python3-pip build-essential libxml2-dev libxslt1-dev zlib1g-dev \
  libsasl2-dev libldap2-dev libjpeg-dev libpq-dev libssl-dev libffi-dev \
  cargo rustc git wget curl

echo "=== 3. Creando usuario del sistema y estructura de directorios ==="
if ! id -u "$ODOO_USER" >/dev/null 2>&1; then
    sudo useradd -m -d $ODOO_HOME -U -r -s /bin/bash $ODOO_USER
fi

# Asignar permisos explícitos sobre la carpeta de Odoo desde el inicio
sudo mkdir -p $ODOO_HOME
sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

echo "=== 4. Configurando usuario en PostgreSQL ==="
sudo -u postgres createuser -s $ODOO_USER 2>/dev/null || true

echo "=== 5. Clonando el repositorio oficial de Odoo $ODOO_VERSION ==="
if [ ! -d "$ODOO_HOME/odoo" ]; then
    sudo -u $ODOO_USER git clone --depth 1 --branch $ODOO_VERSION https://www.github.com/odoo/odoo $ODOO_HOME/odoo
fi

echo "=== 6. Creando entorno virtual (Python 3.12) y ajustando permisos ==="
# Forzamos la creación del venv con Python 3.12 a nombre del usuario 'odoo'
sudo -u $ODOO_USER python3.12 -m venv $ODOO_HOME/venv

echo "=== 7. Instalando paquetes de Python (requirements.txt) ==="
# Actualizamos pip, setuptools y wheel antes de compilar dependencias
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install --upgrade pip setuptools wheel

# Instalamos los requerimientos de la versión 19
sudo -u $ODOO_USER $ODOO_HOME/venv/bin/pip install -r $ODOO_HOME/odoo/requirements.txt

echo "=== 8. Instalando wkhtmltopdf (Reportes PDF) ==="
cd /tmp
wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb -O wkhtmltox.deb
sudo apt install -y ./wkhtmltox.deb
rm -f wkhtmltox.deb

echo "=== 9. Creando directorios para módulos personalizados y logs ==="
sudo mkdir -p $ODOO_HOME/custom-addons
sudo mkdir -p /var/log/odoo

# Ajuste global de propiedad sobre todas las rutas de Odoo
sudo chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME
sudo chown -R $ODOO_USER:$ODOO_USER /var/log/odoo

echo "=== 10. Generando archivo de configuración /etc/odoo.conf ==="
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

echo "=== 11. Creando servicio de systemd para autoinicio ==="
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

sudo systemctl daemon-reload
sudo systemctl enable --now odoo

echo ""
echo "============================================================"
echo " ¡Odoo $ODOO_VERSION instalado correctamente!"
echo " Contraseña maestra de BD (admin_passwd): $ADMIN_PASSWD"
echo " Guarda tu contraseña en un lugar seguro."
echo ""
echo " Accede a la interfaz web en: http://<IP_DE_TU_SERVIDOR>:$ODOO_PORT"
echo "============================================================"
