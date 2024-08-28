#!/bin/bash

# Definir variables
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="manage_proxy.sh"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/master/manage_proxy.sh"

# Función para instalar dependencias
install_dependencies() {
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get update
        sudo apt-get install -y curl wget python3 netstat-nat
    else
        echo "No se pudo encontrar el gestor de paquetes apt-get. Por favor, instale manualmente curl, wget, python3 y netstat-nat."
        exit 1
    fi
}

# Instalar dependencias
install_dependencies

# Crear el directorio de instalación si no existe
mkdir -p "$INSTALL_DIR"

# Descargar el script
echo "Descargando $SCRIPT_NAME..."
curl -sSL "$GITHUB_RAW_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"

# Hacer el script ejecutable
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Agregar el directorio al PATH si no está ya
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$HOME/.bashrc"
    echo "Se ha añadido $INSTALL_DIR a su PATH."
fi

# Crear un alias
echo "alias proxy-manager='$INSTALL_DIR/$SCRIPT_NAME'" >> "$HOME/.bashrc"

# Aplicar los cambios inmediatamente
source "$HOME/.bashrc"

echo "Instalación completada. El comando 'proxy-manager' está ahora disponible."
echo "Puede ejecutar 'proxy-manager' en cualquier momento para gestionar el proxy WebSocket."

# Modificar el script manage_proxy.sh para hacerlo compatible con Debian
sed -i 's|/tmp/proxy.log|/var/log/websocket-proxy.log|g' "$INSTALL_DIR/$SCRIPT_NAME"
sed -i 's|/usr/bin/python3|$(which python3)|g' "$INSTALL_DIR/$SCRIPT_NAME"

# Agregar comprobación de systemctl
sed -i '1s|^|#!/bin/bash\n\nif ! command -v systemctl &> /dev/null; then\n    echo "systemctl no está disponible. Este script requiere systemd."\n    exit 1\nfi\n\n|' "$INSTALL_DIR/$SCRIPT_NAME"

echo "El script manage_proxy.sh ha sido modificado para ser compatible con Debian y Ubuntu."
