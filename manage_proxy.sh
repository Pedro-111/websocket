#!/bin/bash

# Configuración de colores para mejor legibilidad
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración global
PROXY_PATH="/usr/local/bin/proxy.py"
SERVICE_NAME="websocket-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/feature/http2-auth/proxy.py"
LOG_FILE="/tmp/proxy.log"
BACKUP_DIR="/var/backups/websocket-proxy"

# Función para manejar errores
handle_error() {
    echo -e "${RED}Error: $1${NC}"
    logger -t "websocket-proxy" "Error: $1"
    return 1
}

# Función para ejecutar comandos como root con manejo de errores
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@" || handle_error "Fallo al ejecutar: $*"
    else
        sudo "$@" || handle_error "Fallo al ejecutar con sudo: $*"
    fi
}

# Verificación inicial del sistema
check_system_requirements() {
    echo "Verificando requisitos del sistema..."
    
    # Verificar systemd
    if ! command -v systemctl &> /dev/null; then
        handle_error "systemctl no está disponible. Este script requiere systemd."
        exit 1
    fi

    # Verificar Python3
    if ! command -v python3 &> /dev/null; then
        handle_error "Python3 no está instalado."
        exit 1
    fi

    # Verificar curl
    if ! command -v curl &> /dev/null; then
        echo "Instalando curl..."
        run_as_root apt-get update
        run_as_root apt-get install -y curl
    fi

    # Crear directorio de backup si no existe
    if [ ! -d "$BACKUP_DIR" ]; then
        run_as_root mkdir -p "$BACKUP_DIR"
    fi
}

# Función mejorada para descargar el script proxy
download_proxy_script() {
    echo -e "${BLUE}Descargando la última versión de proxy.py...${NC}"
    
    # Crear backup si existe una versión anterior
    if [ -f "$PROXY_PATH" ]; then
        local backup_file="$BACKUP_DIR/proxy.py.backup.$(date +%Y%m%d_%H%M%S)"
        run_as_root cp "$PROXY_PATH" "$backup_file"
        echo "Backup creado en: $backup_file"
    fi

    # Descargar nuevo script
    if run_as_root curl -sSL "$GITHUB_RAW_URL" -o "$PROXY_PATH"; then
        run_as_root chmod +x "$PROXY_PATH"
        echo -e "${GREEN}proxy.py actualizado exitosamente.${NC}"
    else
        handle_error "Fallo al descargar proxy.py"
        # Restaurar backup si existe
        if [ -f "$backup_file" ]; then
            run_as_root cp "$backup_file" "$PROXY_PATH"
            echo "Restaurado desde backup."
        fi
        return 1
    fi
}

# Función mejorada para crear el servicio
create_service() {
    local ports=$1
    echo -e "${BLUE}Creando archivo de servicio con puertos: $ports${NC}"
    
    # Validar puertos
    for port in $ports; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            handle_error "Puerto inválido: $port"
            return 1
        fi
    done

    # Crear archivo de servicio con más opciones de seguridad
    cat << EOF | run_as_root tee "$SERVICE_FILE"
[Unit]
Description=WebSocket Proxy Service
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$(which python3) $PROXY_PATH $ports
Restart=always
RestartSec=3
User=nobody
Group=nogroup
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=yes
PrivateTmp=yes
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}Archivo de servicio creado y configurado.${NC}"
    run_as_root systemctl daemon-reload
    run_as_root systemctl enable $SERVICE_NAME
    run_as_root systemctl start $SERVICE_NAME
    
    # Verificar estado del servicio
    if ! systemctl is-active --quiet $SERVICE_NAME; then
        handle_error "El servicio no se pudo iniciar correctamente."
        run_as_root systemctl status $SERVICE_NAME
        return 1
    fi
}

# Función mejorada para abrir puertos
open_port() {
    check_proxy_script
    
    echo -e "${YELLOW}Ingrese los puertos para el WebSocket (separados por espacios):${NC}"
    read -r new_ports

    # Validar entrada
    if [ -z "$new_ports" ]; then
        handle_error "No se proporcionaron puertos."
        return 1
    fi

    # Verificar si los puertos están en uso
    for port in $new_ports; do
        if netstat -tuln | grep -q ":$port "; then
            handle_error "El puerto $port ya está en uso por otro servicio."
            return 1
        fi
    done

    if [ -f "$SERVICE_FILE" ]; then
        current_ports=$(run_as_root grep ExecStart "$SERVICE_FILE" | awk '{for(i=NF;i>0;i--) if($i ~ /^[0-9]+$/) print $i}')
        all_ports=$(echo "$current_ports $new_ports" | tr ' ' '\n' | sort -u | tr '\n' ' ')
        
        if [ "$all_ports" = "$current_ports" ]; then
            echo -e "${YELLOW}No se han añadido nuevos puertos. Los puertos solicitados ya están en uso.${NC}"
            return 0
        fi
        
        # Crear backup del archivo de servicio
        run_as_root cp "$SERVICE_FILE" "$BACKUP_DIR/service.backup.$(date +%Y%m%d_%H%M%S)"
        
        run_as_root sed -i "s|ExecStart=.*|ExecStart=$(which python3) $PROXY_PATH $all_ports|" "$SERVICE_FILE"
    else
        create_service "$new_ports"
    fi

    run_as_root systemctl daemon-reload
    if ! run_as_root systemctl restart $SERVICE_NAME; then
        handle_error "Error al reiniciar el servicio."
        run_as_root systemctl status $SERVICE_NAME
        return 1
    fi

    echo -e "${GREEN}Puertos WebSocket actualizados exitosamente.${NC}"
}

# Función mejorada para cerrar puertos
close_port() {
    if [ ! -f "$SERVICE_FILE" ]; then
        handle_error "El servicio WebSocket no está instalado."
        return 1
    fi

    current_ports=$(run_as_root grep ExecStart "$SERVICE_FILE" | awk '{for(i=NF;i>0;i--) if($i ~ /^[0-9]+$/) print $i}')
    echo -e "${YELLOW}Puertos actuales: $current_ports${NC}"
    echo -e "Ingrese el puerto a cerrar (o 'all' para cerrar todos):"
    read -r port

    if [ "$port" != "all" ] && ! echo "$current_ports" | grep -q "$port"; then
        handle_error "El puerto $port no está en la configuración actual."
        return 1
    fi

    # Crear backup antes de modificar
    run_as_root cp "$SERVICE_FILE" "$BACKUP_DIR/service.backup.$(date +%Y%m%d_%H%M%S)"

    if [ "$port" == "all" ]; then
        run_as_root systemctl stop $SERVICE_NAME
        run_as_root systemctl disable $SERVICE_NAME
        run_as_root rm "$SERVICE_FILE"
        run_as_root systemctl daemon-reload
        echo -e "${GREEN}Servicio WebSocket detenido y deshabilitado. Todos los puertos cerrados.${NC}"
    else
        new_ports=$(echo "$current_ports" | tr ' ' '\n' | grep -v "^$port$" | tr '\n' ' ')
        new_ports=$(echo "$new_ports" | xargs)

        if [ -z "$new_ports" ]; then
            run_as_root systemctl stop $SERVICE_NAME
            run_as_root systemctl disable $SERVICE_NAME
            run_as_root rm "$SERVICE_FILE"
            run_as_root systemctl daemon-reload
            echo -e "${GREEN}Último puerto cerrado. Servicio WebSocket detenido y deshabilitado.${NC}"
        else
            run_as_root sed -i "s|ExecStart=.*|ExecStart=$(which python3) $PROXY_PATH $new_ports|" "$SERVICE_FILE"
            run_as_root systemctl daemon-reload
            run_as_root systemctl restart $SERVICE_NAME
            echo -e "${GREEN}Puerto $port cerrado. Servicio actualizado con los puertos restantes: $new_ports${NC}"
        fi
    fi
}

# Función mejorada para actualizar scripts
update_script() {
    echo -e "${BLUE}Iniciando proceso de actualización...${NC}"
    
    # Crear backups
    if [ -f "$PROXY_PATH" ]; then
        run_as_root cp "$PROXY_PATH" "$BACKUP_DIR/proxy.py.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    run_as_root cp "$0" "$BACKUP_DIR/manage_proxy.backup.$(date +%Y%m%d_%H%M%S)"

    # Actualizar proxy.py
    if ! download_proxy_script; then
        return 1
    fi

    # Actualizar manage_proxy.sh
    echo -e "${BLUE}Actualizando manage_proxy.sh...${NC}"
    TEMP_SCRIPT="/tmp/manage_proxy_temp.sh"
    if ! wget -O "$TEMP_SCRIPT" "https://raw.githubusercontent.com/Pedro-111/websocket/ubuntu-debian/manage_proxy.sh"; then
        handle_error "Error al descargar manage_proxy.sh"
        return 1
    fi
    
    if [ -f "$TEMP_SCRIPT" ]; then
        run_as_root mv "$TEMP_SCRIPT" "$0"
        run_as_root chmod +x "$0"
        echo -e "${GREEN}manage_proxy.sh actualizado.${NC}"
        
        # Reiniciar el servicio si está activo
        if systemctl is-active --quiet $SERVICE_NAME; then
            run_as_root systemctl restart $SERVICE_NAME
            echo -e "${GREEN}Servicio reiniciado con la nueva versión de los scripts.${NC}"
        fi
        
        echo -e "${YELLOW}Por favor, reinicie el script para aplicar los cambios.${NC}"
        exit 0
    else
        handle_error "Error al actualizar manage_proxy.sh"
        return 1
    fi
}

# Función mejorada para desinstalar
uninstall_script() {
    echo -e "${RED}Proceso de desinstalación iniciado.${NC}"

    # Crear backup final antes de desinstalar
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    run_as_root mkdir -p "$BACKUP_DIR/uninstall_$backup_timestamp"
    
    if [ -f "$PROXY_PATH" ]; then
        run_as_root cp "$PROXY_PATH" "$BACKUP_DIR/uninstall_$backup_timestamp/"
    fi
    run_as_root cp "$0" "$BACKUP_DIR/uninstall_$backup_timestamp/"
    if [ -f "$SERVICE_FILE" ]; then
        run_as_root cp "$SERVICE_FILE" "$BACKUP_DIR/uninstall_$backup_timestamp/"
    fi

    if confirm "¿Desea detener el servicio de WebSocket?"; then
        run_as_root systemctl stop $SERVICE_NAME
        run_as_root systemctl disable $SERVICE_NAME
        run_as_root rm -f "$SERVICE_FILE"
        run_as_root systemctl daemon-reload
        echo -e "${GREEN}Servicio de WebSocket detenido y eliminado.${NC}"
    fi

    if confirm "¿Desea eliminar los scripts y archivos relacionados?"; then
        run_as_root rm -f "$PROXY_PATH"
        # Eliminar alias si existe
        if grep -q "alias proxy-manager=" "$HOME/.bashrc"; then
            sed -i '/alias proxy-manager=/d' "$HOME/.bashrc"
            echo "Alias removido."
        fi
        echo -e "${GREEN}Scripts eliminados.${NC}"
        echo -e "${YELLOW}Se ha creado un backup en: $BACKUP_DIR/uninstall_$backup_timestamp${NC}"
        echo "Por favor, reinicie su terminal o ejecute 'source ~/.bashrc' para aplicar los cambios."
        run_as_root rm -f "$0"
        exit 0
    fi

    echo -e "${GREEN}Proceso de desinstalación completado.${NC}"
}

# Función mejorada para ver puertos abiertos
view_open_ports() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}El servicio WebSocket no está instalado.${NC}"
        return 0
    fi

    echo -e "${BLUE}=== Estado de Puertos WebSocket ===${NC}"
    printf "%-10s %-15s %-20s\n" "Puerto" "Estado" "Conexiones"
    echo "------------------------------------------------"
    
    current_ports=$(run_as_root grep ExecStart "$SERVICE_FILE" | awk '{for(i=NF;i>0;i--) if($i ~ /^[0-9]+$/) print $i}')
    service_status=$(systemctl is-active $SERVICE_NAME)
    
    if [ -z "$current_ports" ]; then
        echo "No se encontraron puertos configurados."
    else
        for port in $current_ports; do
            if [ "$service_status" = "active" ] && run_as_root netstat -tuln | grep -q ":$port "; then
                status="${GREEN}Activo${NC}"
                connections=$(run_as_root netstat -tn | grep ":$port " | wc -l)
            else
                status="${RED}Inactivo${NC}"
                connections="0"
            fi
            printf "%-10s %-15b %-20s\n" "$port" "$status" "$connections"
        done
    fi
    
    echo "------------------------------------------------"
    echo -e "Estado del servicio: ${BLUE}$service_status${NC}"
    
    # Mostrar uso de memoria y CPU
    if [ "$service_status" = "active" ]; then
        echo -e "\nUso de recursos:"
        ps aux | grep "[p]roxy.py" | awk '{printf "CPU: %.1f%%, Memoria: %.1f%%\n", $3, $4}'
    fi
}

# Función mejorada para ver logs
view_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        handle_error "El archivo de log no existe en $LOG_FILE"
        return 1
    fi

    echo -e "${BLUE}=== Log de Conexiones WebSocket ===${NC}"
    echo "Opciones disponibles:"
    echo "1. Ver últimas 20 líneas"
    echo "2. Ver logs en tiempo real"
    echo "3. Buscar en logs"
    echo "4. Volver al menú principal"
    
    read -p "Seleccione una opción: " log_choice
    
    case $log_choice in
        1)
            echo -e "${YELLOW}Últimas 20 líneas del log:${NC}"
            run_as_root tail -n 20 "$LOG_FILE"
            ;;
        2)
            echo -e "${YELLOW}Mostrando logs en tiempo real (Ctrl+C para salir):${NC}"
            run_as_root tail -f "$LOG_FILE"
            ;;
        3)
            read -p "Ingrese el término a buscar: " search_term
            echo -e "${YELLOW}Resultados de la búsqueda:${NC}"
            run_as_root grep -i "$search_term" "$LOG_FILE" || echo "No se encontraron coincidencias."
            ;;
        4)
            return 0
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}"
            ;;
    esac
}

# Función mejorada para confirmar acciones
confirm() {
    while true; do
        read -p "$1 (s/n): " choice
        case "$choice" in
            [Ss]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo -e "${RED}Por favor, responda con 's' o 'n'.${NC}";;
        esac
    done
}


# Nueva función para verificar actualizaciones
check_updates() {
    echo -e "${BLUE}Verificando actualizaciones...${NC}"
    
    # Verificar proxy.py
    TEMP_FILE="/tmp/proxy.py.tmp"
    if curl -sSL "$GITHUB_RAW_URL" -o "$TEMP_FILE"; then
        if [ -f "$PROXY_PATH" ]; then
            if ! cmp -s "$TEMP_FILE" "$PROXY_PATH"; then
                echo -e "${YELLOW}Hay una nueva versión de proxy.py disponible.${NC}"
                return 0
            fi
        fi
    fi
    
    echo -e "${GREEN}No hay actualizaciones disponibles.${NC}"
    return 1
}
monitor_connections() {
    echo -e "${BLUE}=== Monitor de Conexiones WebSocket en Tiempo Real ===${NC}"
    echo -e "${YELLOW}Presione Ctrl+C para salir${NC}\n"
    
    # Función para verificar si una conexión está realmente activa
    check_active_connection() {
        local ip=$1
        local port=$2
        netstat -tnp 2>/dev/null | grep -q "$ip:$port"
        return $?
    }

    while true; do
        clear
        echo -e "${BLUE}=== Monitor de Conexiones WebSocket ===${NC}"
        echo "Fecha/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
        echo -e "\n${GREEN}Conexiones activas:${NC}"
        printf "%-20s %-15s %-12s %-12s %-15s\n" "IP:Puerto" "Host Destino" "Enviado" "Recibido" "Tiempo Conexión"
        echo "--------------------------------------------------------------------------------"
        
        if [ -f "$LOG_FILE" ]; then
            # Crear un archivo temporal para las conexiones activas
            TEMP_FILE=$(mktemp)
            
            # Obtener las conexiones activas usando netstat
            netstat -tn | grep ESTABLISHED | grep ":$(grep ExecStart "$SERVICE_FILE" | grep -o '[0-9]\+' | tr '\n' '|' | sed 's/|$//')" | while read line; do
                remote_addr=$(echo $line | awk '{print $5}')
                local_port=$(echo $line | awk '{print $4}' | cut -d: -f2)
                
                # Buscar información adicional en el log
                connect_time=$(grep "Nueva conexión.*$remote_addr" "$LOG_FILE" | tail -n1 | awk '{print $1" "$2}')
                if [ ! -z "$connect_time" ]; then
                    start_time=$(date -d "$connect_time" +%s)
                    current_time=$(date +%s)
                    duration=$((current_time - start_time))
                    
                    # Solo mostrar si la duración es menor a 5 minutos (300 segundos)
                    if [ $duration -lt 300 ]; then
                        printf "%-20s %-15s %-12s %-12s %-15s\n" \
                            "$remote_addr" \
                            "Puerto $local_port" \
                            "-" \
                            "-" \
                            "$(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60)))"
                    fi
                fi
            done
            
            rm -f "$TEMP_FILE"
        else
            echo "No hay conexiones activas"
        fi
        
        sleep 2
    done
}
# Función principal mejorada
#!/bin/bash

# ... [mantén toda la configuración de colores y variables globales existentes] ...

# Función para verificar si proxy.py existe
check_proxy_script() {
    if [ ! -f "$PROXY_PATH" ]; then
        echo -e "${YELLOW}proxy.py no encontrado. Descargando...${NC}"
        if ! download_proxy_script; then
            handle_error "No se pudo descargar proxy.py"
            exit 1
        fi
    fi
}

# Función para abrir puerto con opciones avanzadas
# Función para generar certificados SSL si no existen
generate_ssl_certificates() {
    local certfile="cert.pem"
    local keyfile="key.pem"
    
    if [ ! -f "$certfile" ] || [ ! -f "$keyfile" ]; then
        echo -e "${YELLOW}Generando certificados SSL...${NC}"
        openssl req -x509 -newkey rsa:4096 \
            -keyout "$keyfile" -out "$certfile" \
            -days 365 -nodes -subj '/CN=localhost' >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Certificados SSL generados correctamente.${NC}"
            return 0
        else
            echo -e "${RED}Error al generar certificados SSL${NC}"
            return 1
        fi
    fi
    return 0
}

# Función para abrir puerto con opciones avanzadas (CORREGIDA)
open_advanced_port() {
    check_proxy_script
    
    echo -e "${BLUE}=== Configuración Avanzada de Puerto ===${NC}"
    
    # Solicitar puerto
    while true; do
        read -p "Ingrese el puerto a abrir: " port
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            if netstat -tuln | grep -q ":$port "; then
                handle_error "El puerto $port ya está en uso por otro servicio."
                continue
            fi
            break
        else
            echo -e "${RED}Puerto inválido. Ingrese un número entre 1 y 65535.${NC}"
        fi
    done
    
    # Configurar SSL
    echo -e "\n${YELLOW}¿Desea habilitar SSL/TLS para este puerto?${NC}"
    if confirm "Habilitar SSL"; then
        use_ssl=true
        ssl_suffix=":ssl"
        
        # Generar certificados SSL si no existen
        if ! generate_ssl_certificates; then
            echo -e "${RED}No se pudieron generar los certificados SSL. El puerto no se abrirá.${NC}"
            return 1
        fi
    else
        use_ssl=false
        ssl_suffix=""
    fi
    
    # Configurar autenticación
    echo -e "\n${YELLOW}¿Desea configurar autenticación básica para este puerto?${NC}"
    if confirm "Habilitar autenticación"; then
        read -p "Ingrese el usuario: " username
        read -s -p "Ingrese la contraseña: " password
        echo
        auth_suffix=":$username:$password"
    else
        auth_suffix=""
    fi
    
    # Construir configuración del puerto (CORREGIDO: solo agregar :ssl si es true)
    if [ "$use_ssl" = true ]; then
        port_config="$port:ssl$auth_suffix"
    else
        port_config="$port$auth_suffix"
    fi
    
    echo -e "\n${BLUE}Resumen de configuración:${NC}"
    echo "Puerto: $port"
    echo "SSL/TLS: $([ "$use_ssl" = true ] && echo "Habilitado" || echo "Deshabilitado")"
    echo "Autenticación: $([ -n "$auth_suffix" ] && echo "Habilitada ($username)" || echo "Deshabilitada")"
    
    if ! confirm "¿Confirma la configuración?"; then
        echo -e "${YELLOW}Configuración cancelada.${NC}"
        return 0
    fi
    
    # Agregar el nuevo puerto a la configuración existente
    if [ -f "$SERVICE_FILE" ]; then
        current_ports=$(run_as_root grep ExecStart "$SERVICE_FILE" | sed 's/.*proxy\.py //')
        
        # Verificar si el puerto ya está configurado
        if echo "$current_ports" | grep -q "\b$port\b"; then
            echo -e "${YELLOW}El puerto $port ya está configurado. Reemplazando configuración...${NC}"
            # Eliminar la configuración existente del puerto
            new_ports=$(echo "$current_ports" | sed -E "s/\b$port(:[^ ]*)?\b//g" | sed 's/  */ /g')
            all_ports="$new_ports $port_config"
        else
            all_ports="$current_ports $port_config"
        fi
        
        # Crear backup
        run_as_root cp "$SERVICE_FILE" "$BACKUP_DIR/service.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Actualizar archivo de servicio
        run_as_root sed -i "s|ExecStart=.*|ExecStart=$(which python3) $PROXY_PATH $all_ports|" "$SERVICE_FILE"
    else
        create_service "$port_config"
    fi
    
    run_as_root systemctl daemon-reload
    sleep 2
    
    # Reiniciar servicio con verificación mejorada
    if ! run_as_root systemctl restart $SERVICE_NAME; then
        handle_error "Error al reiniciar el servicio."
        # Mostrar detalles del error
        echo -e "${YELLOW}Intentando iniciar el servicio...${NC}"
        if ! run_as_root systemctl start $SERVICE_NAME; then
            run_as_root journalctl -u $SERVICE_NAME -n 10 --no-pager
            return 1
        fi
    fi
    
    # Verificar que el servicio esté activo
    sleep 2
    if run_as_root systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}Puerto $port configurado exitosamente.${NC}"
        if [ "$use_ssl" = true ]; then
            echo -e "${YELLOW}Nota: Se utilizan los certificados SSL generados automáticamente.${NC}"
        fi
    else
        handle_error "El servicio no se pudo iniciar correctamente."
        run_as_root systemctl status $SERVICE_NAME
        return 1
    fi
}
# Función para gestionar ACL (Lista de Control de Acceso)
manage_acl() {
    echo -e "${BLUE}=== Gestión de Lista de Control de Acceso (ACL) ===${NC}"
    
    local config_file="config.ini"
    
    echo "1. Ver ACL actual"
    echo "2. Agregar IP a la lista blanca"
    echo "3. Eliminar IP de la lista blanca"
    echo "4. Limpiar toda la ACL"
    echo "5. Volver al menú principal"
    
    read -p "Seleccione una opción: " acl_choice
    
    case $acl_choice in
        1)
            if [ -f "$config_file" ] && grep -q "\[ACL\]" "$config_file"; then
                echo -e "${YELLOW}ACL actual:${NC}"
                grep -A1 "\[ACL\]" "$config_file" | grep "pages =" | cut -d'=' -f2 | tr ',' '\n' | sed 's/^ */- /'
            else
                echo -e "${YELLOW}No hay ACL configurada (acceso libre).${NC}"
            fi
            ;;
        2)
            read -p "Ingrese la IP a agregar: " new_ip
            if [[ "$new_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                create_or_update_config_section "ACL" "pages" "$new_ip" "$config_file"
                echo -e "${GREEN}IP $new_ip agregada a la ACL.${NC}"
            else
                handle_error "Formato de IP inválido."
            fi
            ;;
        3)
            if [ -f "$config_file" ] && grep -q "\[ACL\]" "$config_file"; then
                current_ips=$(grep -A1 "\[ACL\]" "$config_file" | grep "pages =" | cut -d'=' -f2)
                echo -e "${YELLOW}IPs actuales: $current_ips${NC}"
                read -p "Ingrese la IP a eliminar: " remove_ip
                remove_from_config_section "ACL" "pages" "$remove_ip" "$config_file"
                echo -e "${GREEN}IP $remove_ip eliminada de la ACL.${NC}"
            else
                echo -e "${YELLOW}No hay ACL configurada.${NC}"
            fi
            ;;
        4)
            if confirm "¿Desea limpiar toda la ACL? Esto permitirá acceso libre"; then
                remove_config_section "ACL" "$config_file"
                echo -e "${GREEN}ACL limpiada. Acceso libre habilitado.${NC}"
            fi
            ;;
        5)
            return 0
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}"
            ;;
    esac
    
    # Reiniciar servicio si está activo
    if systemctl is-active --quiet $SERVICE_NAME; then
        if confirm "¿Desea reiniciar el servicio para aplicar los cambios?"; then
            run_as_root systemctl restart $SERVICE_NAME
            echo -e "${GREEN}Servicio reiniciado.${NC}"
        fi
    fi
}

# Función para gestionar páginas bloqueadas
manage_blocked_pages() {
    echo -e "${BLUE}=== Gestión de Páginas Bloqueadas ===${NC}"
    
    local config_file="config.ini"
    
    echo "1. Ver páginas bloqueadas"
    echo "2. Agregar página a la lista de bloqueo"
    echo "3. Eliminar página de la lista de bloqueo"
    echo "4. Limpiar lista de páginas bloqueadas"
    echo "5. Volver al menú principal"
    
    read -p "Seleccione una opción: " block_choice
    
    case $block_choice in
        1)
            if [ -f "$config_file" ] && grep -q "\[BlockedPages\]" "$config_file"; then
                echo -e "${YELLOW}Páginas bloqueadas:${NC}"
                grep -A1 "\[BlockedPages\]" "$config_file" | grep "pages =" | cut -d'=' -f2 | tr ',' '\n' | sed 's/^ */- /'
            else
                echo -e "${YELLOW}No hay páginas bloqueadas.${NC}"
            fi
            ;;
        2)
            read -p "Ingrese el dominio a bloquear (ej: facebook.com): " new_domain
            if [[ "$new_domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                create_or_update_config_section "BlockedPages" "pages" "$new_domain" "$config_file"
                echo -e "${GREEN}Dominio $new_domain agregado a la lista de bloqueo.${NC}"
            else
                handle_error "Formato de dominio inválido."
            fi
            ;;
        3)
            if [ -f "$config_file" ] && grep -q "\[BlockedPages\]" "$config_file"; then
                current_domains=$(grep -A1 "\[BlockedPages\]" "$config_file" | grep "pages =" | cut -d'=' -f2)
                echo -e "${YELLOW}Dominios bloqueados: $current_domains${NC}"
                read -p "Ingrese el dominio a desbloquear: " remove_domain
                remove_from_config_section "BlockedPages" "pages" "$remove_domain" "$config_file"
                echo -e "${GREEN}Dominio $remove_domain eliminado de la lista de bloqueo.${NC}"
            else
                echo -e "${YELLOW}No hay páginas bloqueadas.${NC}"
            fi
            ;;
        4)
            if confirm "¿Desea limpiar toda la lista de páginas bloqueadas?"; then
                remove_config_section "BlockedPages" "$config_file"
                echo -e "${GREEN}Lista de páginas bloqueadas limpiada.${NC}"
            fi
            ;;
        5)
            return 0
            ;;
        *)
            echo -e "${RED}Opción inválida${NC}"
            ;;
    esac
    
    # Reiniciar servicio si está activo
    if systemctl is-active --quiet $SERVICE_NAME; then
        if confirm "¿Desea reiniciar el servicio para aplicar los cambios?"; then
            run_as_root systemctl restart $SERVICE_NAME
            echo -e "${GREEN}Servicio reiniciado.${NC}"
        fi
    fi
}

# Funciones auxiliares para manejar archivos de configuración
create_or_update_config_section() {
    local section=$1
    local key=$2
    local new_value=$3
    local config_file=$4
    
    if [ ! -f "$config_file" ]; then
        touch "$config_file"
    fi
    
    if ! grep -q "\[$section\]" "$config_file"; then
        echo "[$section]" >> "$config_file"
        echo "$key = $new_value" >> "$config_file"
    else
        if grep -q "$key =" "$config_file"; then
            current_value=$(grep -A1 "\[$section\]" "$config_file" | grep "$key =" | cut -d'=' -f2 | sed 's/^ *//')
            if [[ "$current_value" != *"$new_value"* ]]; then
                new_combined="$current_value, $new_value"
                sed -i "/\[$section\]/,/^\[/ s/$key = .*/$key = $new_combined/" "$config_file"
            fi
        else
            sed -i "/\[$section\]/a $key = $new_value" "$config_file"
        fi
    fi
}

remove_from_config_section() {
    local section=$1
    local key=$2
    local remove_value=$3
    local config_file=$4
    
    if [ -f "$config_file" ] && grep -q "\[$section\]" "$config_file"; then
        current_value=$(grep -A1 "\[$section\]" "$config_file" | grep "$key =" | cut -d'=' -f2 | sed 's/^ *//')
        new_value=$(echo "$current_value" | sed "s/$remove_value,\? *//g" | sed 's/^, *//' | sed 's/, *$//')
        
        if [ -z "$new_value" ]; then
            remove_config_section "$section" "$config_file"
        else
            sed -i "/\[$section\]/,/^\[/ s/$key = .*/$key = $new_value/" "$config_file"
        fi
    fi
}

remove_config_section() {
    local section=$1
    local config_file=$2
    
    if [ -f "$config_file" ]; then
        sed -i "/^\[$section\]/,/^\[.*\]/{ /^\[$section\]/d; /^\[.*\]/!d; }" "$config_file"
        sed -i "/^\[$section\]/d" "$config_file"
    fi
}

# Función mejorada para ver configuración completa
view_full_configuration() {
    echo -e "${BLUE}=== Configuración Completa del Proxy ===${NC}"
    
    # Estado del servicio
    echo -e "\n${YELLOW}Estado del Servicio:${NC}"
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "Servicio: ${GREEN}Activo${NC}"
        uptime=$(systemctl show $SERVICE_NAME --property=ActiveEnterTimestamp --value)
        echo "Iniciado: $uptime"
    else
        echo -e "Servicio: ${RED}Inactivo${NC}"
    fi
    
    # Puertos configurados
    echo -e "\n${YELLOW}Puertos Configurados:${NC}"
    if [ -f "$SERVICE_FILE" ]; then
        current_config=$(run_as_root grep ExecStart "$SERVICE_FILE" | sed 's/.*proxy\.py //')
        echo "------------------------------------------------"
        printf "%-8s %-6s %-15s %-15s\n" "Puerto" "SSL" "Usuario" "Estado"
        echo "------------------------------------------------"
        
        for config in $current_config; do
            IFS=':' read -ra PARTS <<< "$config"
            port=${PARTS[0]}
            ssl="No"
            username="-"
            
            # Verificar SSL
            if [[ " ${PARTS[@]} " =~ " ssl " ]]; then
                ssl="Sí"
            fi
            
            # Verificar usuario
            for i in "${!PARTS[@]}"; do
                if [[ ${PARTS[$i]} != "ssl" && $i -gt 0 && ${PARTS[$i]} =~ ^[a-zA-Z] ]]; then
                    username=${PARTS[$i]}
                    break
                fi
            done
            
            # Estado del puerto
            if systemctl is-active --quiet $SERVICE_NAME && netstat -tuln | grep -q ":$port "; then
                status="${GREEN}Activo${NC}"
            else
                status="${RED}Inactivo${NC}"
            fi
            
            printf "%-8s %-6s %-15s %-15b\n" "$port" "$ssl" "$username" "$status"
        done
    else
        echo "No hay puertos configurados"
    fi
    
    # ACL
    echo -e "\n${YELLOW}Lista de Control de Acceso (ACL):${NC}"
    if [ -f "config.ini" ] && grep -q "\[ACL\]" "config.ini"; then
        grep -A1 "\[ACL\]" "config.ini" | grep "pages =" | cut -d'=' -f2 | tr ',' '\n' | sed 's/^ */  - /'
    else
        echo "  Sin restricciones (acceso libre)"
    fi
    
    # Páginas bloqueadas
    echo -e "\n${YELLOW}Páginas Bloqueadas:${NC}"
    if [ -f "config.ini" ] && grep -q "\[BlockedPages\]" "config.ini"; then
        grep -A1 "\[BlockedPages\]" "config.ini" | grep "pages =" | cut -d'=' -f2 | tr ',' '\n' | sed 's/^ */  - /'
    else
        echo "  Ninguna página bloqueada"
    fi
    
    # Estadísticas de conexiones
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "\n${YELLOW}Estadísticas de Conexiones:${NC}"
        total_connections=$(grep -c "Nueva conexión" /var/tmp/proxy.log 2>/dev/null || echo "0")
        echo "  Total de conexiones registradas: $total_connections"
        
        # Conexiones por IP (top 5)
        if [ -f "/var/tmp/proxy.log" ]; then
            echo -e "\n  Top 5 IPs conectadas:"
            grep "Nueva conexión" /var/tmp/proxy.log | awk '{print $NF}' | sort | uniq -c | sort -nr | head -5 | while read count ip; do
                echo "    $ip: $count conexiones"
            done
        fi
    fi
}

# MAIN MEJORADO Y MÁS ORGANIZADO
main() {
    # Banner del script
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              🌐 GESTIÓN DE PROXY WEBSOCKET 🌐              ║"
    echo "║                     Versión Avanzada                     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Verificar que se ejecute como root
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}Este script necesita privilegios de superusuario.${NC}"
        exec sudo "$0" "$@"
    fi

    # Verificar requisitos del sistema
    check_system_requirements

    while true; do
        echo -e "\n${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${BLUE}│                  MENÚ PRINCIPAL                         │${NC}"
        echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"
        
        # Mostrar estado actual
        if systemctl is-active --quiet $SERVICE_NAME 2>/dev/null; then
            current_ports=$(run_as_root grep ExecStart "$SERVICE_FILE" 2>/dev/null | sed 's/.*proxy\.py //' || echo "Ninguno")
            echo -e "${GREEN}📡 Estado: Servicio activo${NC}"
            echo -e "${GREEN}🔌 Puertos activos: $current_ports${NC}"
        else
            echo -e "${RED}📡 Estado: Servicio inactivo${NC}"
        fi
        
        echo -e "\n${YELLOW}╭─ GESTIÓN DE PUERTOS ─────────────────────────────────────╮${NC}"
        echo -e "${YELLOW}│${NC} 1. 🚀 Abrir puerto simple (método rápido)              ${YELLOW}│${NC}"
        echo -e "${YELLOW}│${NC} 2. ⚙️  Abrir puerto avanzado (SSL/Auth)                 ${YELLOW}│${NC}"
        echo -e "${YELLOW}│${NC} 3. ❌ Cerrar puerto específico                          ${YELLOW}│${NC}"
        echo -e "${YELLOW}│${NC} 4. 📊 Ver puertos y estado                             ${YELLOW}│${NC}"
        echo -e "${YELLOW}╰─────────────────────────────────────────────────────────╯${NC}"
        
        echo -e "\n${CYAN}╭─ SEGURIDAD Y CONTROL ────────────────────────────────────╮${NC}"
        echo -e "${CYAN}│${NC} 5. 🛡️  Gestionar ACL (Control de acceso)               ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC} 6. 🚫 Gestionar páginas bloqueadas                     ${CYAN}│${NC}"
        echo -e "${CYAN}│${NC} 7. 📋 Ver configuración completa                       ${CYAN}│${NC}"
        echo -e "${CYAN}╰─────────────────────────────────────────────────────────╯${NC}"
        
        echo -e "\n${BLUE}╭─ MONITOREO Y LOGS ───────────────────────────────────────╮${NC}"
        echo -e "${BLUE}│${NC} 8. 📄 Ver logs de conexiones                           ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC} 9. 📱 Monitor en tiempo real                           ${BLUE}│${NC}"
        echo -e "${BLUE}╰─────────────────────────────────────────────────────────╯${NC}"
        
        echo -e "\n${GREEN}╭─ MANTENIMIENTO ──────────────────────────────────────────╮${NC}"
        echo -e "${GREEN}│${NC} 10. 🔄 Actualizar scripts                              ${GREEN}│${NC}"
        echo -e "${GREEN}│${NC} 11. 🔍 Verificar actualizaciones                       ${GREEN}│${NC}"
        echo -e "${GREEN}│${NC} 12. 🗑️  Desinstalar completamente                      ${GREEN}│${NC}"
        echo -e "${GREEN}╰─────────────────────────────────────────────────────────╯${NC}"
        
        echo -e "\n${RED}╭─ SALIR ──────────────────────────────────────────────────╮${NC}"
        echo -e "${RED}│${NC} 0. 👋 Salir del programa                               ${RED}│${NC}"
        echo -e "${RED}╰─────────────────────────────────────────────────────────╯${NC}"
        
        echo -e "\n${YELLOW}Seleccione una opción [0-12]:${NC} \c"
        read choice

        case $choice in
            1)
                echo -e "\n${BLUE}🚀 Abriendo puerto simple...${NC}"
                open_port
                ;;
            2)
                echo -e "\n${BLUE}⚙️ Configuración avanzada de puerto...${NC}"
                open_advanced_port
                ;;
            3)
                echo -e "\n${BLUE}❌ Cerrando puerto...${NC}"
                close_port
                ;;
            4)
                echo -e "\n${BLUE}📊 Mostrando estado de puertos...${NC}"
                view_open_ports
                ;;
            5)
                echo -e "\n${BLUE}🛡️ Gestionando ACL...${NC}"
                manage_acl
                ;;
            6)
                echo -e "\n${BLUE}🚫 Gestionando páginas bloqueadas...${NC}"
                manage_blocked_pages
                ;;
            7)
                echo -e "\n${BLUE}📋 Mostrando configuración completa...${NC}"
                view_full_configuration
                ;;
            8)
                echo -e "\n${BLUE}📄 Mostrando logs...${NC}"
                view_logs
                ;;
            9)
                echo -e "\n${BLUE}📱 Iniciando monitor en tiempo real...${NC}"
                monitor_connections
                ;;
            10)
                echo -e "\n${BLUE}🔄 Actualizando scripts...${NC}"
                update_script
                ;;
            11)
                echo -e "\n${BLUE}🔍 Verificando actualizaciones...${NC}"
                check_updates
                ;;
            12)
                echo -e "\n${BLUE}🗑️ Iniciando desinstalación...${NC}"
                uninstall_script
                ;;
            0)
                echo -e "\n${GREEN}👋 ¡Gracias por usar el Gestor de Proxy WebSocket!${NC}"
                echo -e "${GREEN}🌟 ¡Que tengas un excelente día! 🌟${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}❌ Opción inválida. Por favor, seleccione un número del 0 al 12.${NC}"
                sleep 2
                ;;
        esac

        echo -e "\n${YELLOW}────────────────────────────────────────────────────────────${NC}"
        echo -e "${YELLOW}Presione Enter para continuar...${NC}"
        read -r
        clear
    done
}

# Manejo de señales mejorado
cleanup_on_exit() {
    echo -e "\n\n${YELLOW}🛑 Operación interrumpida por el usuario.${NC}"
    echo -e "${BLUE}🧹 Limpiando recursos...${NC}"
    exit 1
}

trap cleanup_on_exit SIGINT SIGTERM

# Limpiar pantalla e iniciar
clear
main "$@"
