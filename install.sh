#!/bin/bash

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar mensajes de error
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Función para ejecutar comandos como root
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Definir variables
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="manage_proxy.sh"
PROXY_SCRIPT="proxy.py"
SERVICE_NAME="websocket-proxy"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
BACKUP_DIR="$HOME/.proxy_backups"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/feature/http2-auth"

# Función para instalar dependencias
install_dependencies() {
    echo -e "${BLUE}Instalando dependencias...${NC}"
    
    # Actualizar lista de paquetes
    if ! run_as_root apt-get update; then
        error_exit "No se pudo actualizar la lista de paquetes"
    fi
    
    # Instalar paquetes necesarios
    local packages=("curl" "wget" "python3" "net-tools" "openssl")
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            echo -e "${YELLOW}Instalando $pkg...${NC}"
            if ! run_as_root apt-get install -y "$pkg"; then
                error_exit "No se pudo instalar $pkg"
            fi
        else
            echo -e "${GREEN}$pkg ya está instalado.${NC}"
        fi
    done
}

# Función para crear directorios necesarios
create_directories() {
    echo -e "${BLUE}Creando directorios necesarios...${NC}"
    
    mkdir -p "$INSTALL_DIR" || error_exit "No se pudo crear $INSTALL_DIR"
    mkdir -p "$BACKUP_DIR" || error_exit "No se pudo crear $BACKUP_DIR"
    
    # Crear archivo de log con permisos adecuados
    run_as_root touch "/var/tmp/proxy.log"
    run_as_root chmod 666 "/var/tmp/proxy.log"
}

# Función para descargar archivos
download_files() {
    echo -e "${BLUE}Descargando archivos necesarios...${NC}"
    
    # Descargar script de gestión
    echo -e "${YELLOW}Descargando $SCRIPT_NAME...${NC}"
    if ! curl -sSL "$GITHUB_RAW_URL/$SCRIPT_NAME" -o "$INSTALL_DIR/$SCRIPT_NAME"; then
        error_exit "No se pudo descargar $SCRIPT_NAME"
    fi
    
    # Descargar script del proxy
    echo -e "${YELLOW}Descargando $PROXY_SCRIPT...${NC}"
    if ! run_as_root curl -sSL "$GITHUB_RAW_URL/$PROXY_SCRIPT" -o "/usr/local/bin/$PROXY_SCRIPT"; then
        error_exit "No se pudo descargar $PROXY_SCRIPT"
    fi
    
    # Hacer los scripts ejecutables
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME" || error_exit "No se pudo hacer ejecutable $SCRIPT_NAME"
    run_as_root chmod +x "/usr/local/bin/$PROXY_SCRIPT" || error_exit "No se pudo hacer ejecutable $PROXY_SCRIPT"
}

# Función para configurar el servicio systemd
setup_service() {
    echo -e "${BLUE}Configurando servicio systemd...${NC}"
    
    # Crear archivo de servicio
    cat << EOF | run_as_root tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=WebSocket Proxy Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/$PROXY_SCRIPT 8080
Restart=always
RestartSec=5
StandardOutput=file:/var/tmp/proxy.log
StandardError=file:/var/tmp/proxy.log

[Install]
WantedBy=multi-user.target
EOF

    # Recargar systemd y habilitar servicio
    run_as_root systemctl daemon-reload
    run_as_root systemctl enable "$SERVICE_NAME"
    
    echo -e "${GREEN}Servicio systemd configurado correctamente.${NC}"
}

# Función para configurar el entorno de usuario
setup_environment() {
    echo -e "${BLUE}Configurando entorno de usuario...${NC}"
    
    # Detectar el shell actual
    local current_shell
    current_shell=$(basename "$SHELL")
    
    # Agregar el directorio al PATH si no está ya
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        if [ "$current_shell" = "bash" ]; then
            echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$HOME/.bashrc"
            echo -e "${GREEN}Se ha añadido $INSTALL_DIR a su PATH en .bashrc.${NC}"
        elif [ "$current_shell" = "zsh" ]; then
            echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$HOME/.zshrc"
            echo -e "${GREEN}Se ha añadido $INSTALL_DIR a su PATH en .zshrc.${NC}"
        else
            echo -e "${YELLOW}Shell no reconocido. Debe agregar manualmente $INSTALL_DIR a su PATH.${NC}"
        fi
    fi
    
    # Crear alias
    if [ "$current_shell" = "bash" ]; then
        echo "alias proxy-manager='$INSTALL_DIR/$SCRIPT_NAME'" >> "$HOME/.bashrc"
    elif [ "$current_shell" = "zsh" ]; then
        echo "alias proxy-manager='$INSTALL_DIR/$SCRIPT_NAME'" >> "$HOME/.zshrc"
    fi
    
    # Aplicar los cambios inmediatamente para la sesión actual
    export PATH="$PATH:$INSTALL_DIR"
    alias proxy-manager="$INSTALL_DIR/$SCRIPT_NAME"
    
    echo -e "${GREEN}Entorno configurado correctamente.${NC}"
}

# Función para generar certificados SSL iniciales
generate_ssl_certificates() {
    echo -e "${BLUE}Generando certificados SSL iniciales...${NC}"
    
    local certfile="cert.pem"
    local keyfile="key.pem"
    
    if [ ! -f "$certfile" ] || [ ! -f "$keyfile" ]; then
        if run_as_root openssl req -x509 -newkey rsa:4096 \
            -keyout "$keyfile" -out "$certfile" \
            -days 365 -nodes -subj '/CN=localhost' >/dev/null 2>&1; then
            echo -e "${GREEN}Certificados SSL generados correctamente.${NC}"
        else
            echo -e "${YELLOW}Advertencia: No se pudieron generar los certificados SSL.${NC}"
        fi
    else
        echo -e "${GREEN}Certificados SSL ya existen.${NC}"
    fi
}

# Función principal de instalación
main_install() {
    echo -e "${BLUE}=== Instalación del Proxy WebSocket ===${NC}"
    
    # Verificar si estamos en un sistema Debian/Ubuntu
    if ! command_exists apt-get; then
        error_exit "Este script solo es compatible con sistemas basados en Debian/Ubuntu"
    fi
    
    # Verificar si ya está instalado
    if [ -f "$INSTALL_DIR/$SCRIPT_NAME" ] && [ -f "/usr/local/bin/$PROXY_SCRIPT" ]; then
        echo -e "${YELLOW}El proxy ya parece estar instalado.${NC}"
        read -p "¿Desea reinstalar? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            echo -e "${YELLOW}Instalación cancelada.${NC}"
            exit 0
        fi
    fi
    
    # Ejecutar los pasos de instalación
    install_dependencies
    create_directories
    download_files
    setup_service
    setup_environment
    generate_ssl_certificates
    
    echo -e "${GREEN}=== Instalación completada ===${NC}"
    echo -e "${GREEN}El comando 'proxy-manager' está ahora disponible.${NC}"
    echo -e "${GREEN}Puede ejecutar 'proxy-manager' en cualquier momento para gestionar el proxy WebSocket.${NC}"
    echo -e "${YELLOW}Nota: Para aplicar los cambios del PATH, puede necesitar cerrar y reabrir su terminal.${NC}"
    
    # Preguntar si quiere iniciar el servicio ahora
    read -p "¿Desea iniciar el servicio ahora? (S/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if run_as_root systemctl start "$SERVICE_NAME"; then
            echo -e "${GREEN}Servicio iniciado correctamente.${NC}"
        else
            echo -e "${YELLOW}No se pudo iniciar el servicio. Puede intentarlo manualmente con: sudo systemctl start $SERVICE_NAME${NC}"
        fi
    fi
}

# Ejecutar instalación
main_install
