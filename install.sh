#!/bin/bash

# Definir variables
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="manage_proxy.sh"
PROXY_SCRIPT="proxy.py"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/debian"

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

# Descargar los scripts
echo "Descargando $SCRIPT_NAME..."
curl -sSL "$GITHUB_RAW_URL/$SCRIPT_NAME" -o "$INSTALL_DIR/$SCRIPT_NAME"
echo "Descargando $PROXY_SCRIPT..."
sudo curl -sSL "$GITHUB_RAW_URL/$PROXY_SCRIPT" -o "/usr/local/bin/$PROXY_SCRIPT"

# Hacer los scripts ejecutables
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
sudo chmod +x "/usr/local/bin/$PROXY_SCRIPT"

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
