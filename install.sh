#!/bin/bash

# Función para ejecutar comandos como root
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Definir variables
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="manage_proxy.sh"
PROXY_SCRIPT="proxy.py"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/ubuntu-debian"

# Función para instalar dependencias
install_dependencies() {
    run_as_root apt-get update
    run_as_root apt-get install -y curl wget python3 net-tools
}

# Instalar dependencias
install_dependencies

# Crear el directorio de instalación si no existe
mkdir -p "$INSTALL_DIR"

# Descargar los scripts
echo "Descargando $SCRIPT_NAME..."
curl -sSL "$GITHUB_RAW_URL/$SCRIPT_NAME" -o "$INSTALL_DIR/$SCRIPT_NAME"
echo "Descargando $PROXY_SCRIPT..."
run_as_root curl -sSL "$GITHUB_RAW_URL/$PROXY_SCRIPT" -o "/usr/local/bin/$PROXY_SCRIPT"

# Hacer los scripts ejecutables
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
run_as_root chmod +x "/usr/local/bin/$PROXY_SCRIPT"

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
