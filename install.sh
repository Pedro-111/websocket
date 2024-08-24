#!/bin/bash

# Definir variables
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="manage_proxy.sh"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/master/manage_proxy.sh"

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
