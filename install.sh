#!/bin/bash

# Definir variables
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="manage_proxy.sh"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/master/manage_proxy.sh"
PROXY_SCRIPT_NAME="proxy.py"
PROXY_GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/master/proxy.py"
PROXY_INSTALL_DIR="/usr/local/bin"

# Crear el directorio de instalación si no existe
mkdir -p "$INSTALL_DIR"

# Descargar el script manage_proxy.sh
echo "Descargando $SCRIPT_NAME..."
curl -sSL "$GITHUB_RAW_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"

# Hacer el script ejecutable
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Descargar el script proxy.py
echo "Descargando $PROXY_SCRIPT_NAME..."
sudo curl -sSL "$PROXY_GITHUB_RAW_URL" -o "$PROXY_INSTALL_DIR/$PROXY_SCRIPT_NAME"

# Hacer el script proxy.py ejecutable
sudo chmod +x "$PROXY_INSTALL_DIR/$PROXY_SCRIPT_NAME"

# Agregar el directorio al PATH si no está ya
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$HOME/.bashrc"
    echo "Se ha añadido $INSTALL_DIR a su PATH."
fi

# Crear un alias
echo "alias proxy-manager='$INSTALL_DIR/$SCRIPT_NAME'" >> "$HOME/.bashrc"

# Aplicar los cambios inmediatamente
source ~/.bashrc

echo "Instalación completada. Ejecuta el comando 'source ~/.bashrc'. El comando 'proxy-manager' estará ahora disponible."
echo "Puede ejecutar 'proxy-manager' en cualquier momento para gestionar el proxy WebSocket."
echo "El script proxy.py ha sido instalado en $PROXY_INSTALL_DIR/$PROXY_SCRIPT_NAME"
