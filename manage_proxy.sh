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
GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/ubuntu-debian/proxy.py"
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

# Función para mostrar estadísticas en tiempo real
show_statistics() {
    # Colores adicionales
    PURPLE='\033[0;35m'
    WHITE='\033[1;37m'
    
    # Array asociativo para conexiones activas por puerto
    declare -A active_connections
    declare -A port_connections_count

    # Función para validar si es una conexión de cliente
    is_client_connection() {
        local ip="$1"
        # Filtrar conexiones localhost/servidor
        if [[ "$ip" == "127.0.0.1" ]] || [[ "$ip" == "::1" ]] || [[ "$ip" == "localhost" ]]; then
            return 1
        fi
        return 0
    }

    # Función para limpiar formato de dirección
    clean_address() {
        local addr="$1"
        # Eliminar caracteres no deseados y espacios
        echo "$addr" | sed -e "s/[()']//g" -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
    }

    # Función para mostrar el encabezado
    show_header() {
        clear
        echo -e "${YELLOW}=== Monitor de Conexiones WebSocket ===${NC}"
        echo -e "${BLUE}Monitoreando conexiones en tiempo real...${NC}"
        echo -e "${PURPLE}Fecha y hora: ${NC}$(date '+%Y-%m-%d %H:%M:%S')"
        echo -e "${YELLOW}Presione 0 para salir${NC}\n"
        
        if systemctl is-active --quiet $SERVICE_NAME; then
            echo -e "${GREEN}Estado del servicio: Activo${NC}"
            
            # Mostrar puertos configurados y su estado
            echo -e "\n${WHITE}Estado de puertos:${NC}"
            echo "╔════════════╦═══════════╦══════════════════╗"
            echo "║   Puerto   ║  Estado   ║    Conexiones    ║"
            echo "╠════════════╬═══════════╬══════════════════╣"
            
            local ports=$(run_as_root grep ExecStart "$SERVICE_FILE" | grep -oP '\d+')
            for port in $ports; do
                local port_status
                local conn_count=${port_connections_count[$port]:-0}
                
                if run_as_root netstat -tuln | grep -q ":$port "; then
                    port_status="${GREEN}Activo${NC}"
                else
                    port_status="${RED}Inactivo${NC}"
                fi
                
                printf "║ %-10s ║ %-25b ║ %-16s ║\n" "$port" "$port_status" "$conn_count"
            done
            echo "╚════════════╩═══════════╩══════════════════╝"
        else
            echo -e "${RED}Estado del servicio: Inactivo${NC}"
            return 1
        fi
        
        # Mostrar uso de recursos
        local cpu_usage=$(ps aux | grep "[p]roxy.py" | awk '{sum+=$3} END {print sum}')
        local mem_usage=$(ps aux | grep "[p]roxy.py" | awk '{sum+=$4} END {print sum}')
        echo -e "\n${BLUE}Uso de recursos:${NC}"
        echo -e "CPU: ${YELLOW}${cpu_usage}%${NC}"
        echo -e "Memoria: ${YELLOW}${mem_usage}%${NC}"
    }

    # Función para procesar cada línea del log
    process_log_line() {
        local line="$1"
        if [[ $line =~ "Nueva conexión" ]]; then
            local addr=$(echo "$line" | grep -oP 'desde \K[^ ]+')
            local ip=$(echo "$addr" | cut -d: -f1)
            local port=$(echo "$addr" | cut -d: -f2)
            
            # Solo procesar conexiones de clientes
            if is_client_connection "$ip"; then
                local timestamp=$(echo "$line" | grep -oP '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')
                active_connections["$addr"]="$timestamp"
                ((port_connections_count[$port]++))
            fi
        elif [[ $line =~ "Conexión cerrada" ]] || [[ $line =~ "Error en conexión" ]]; then
            local addr=$(echo "$line" | grep -oP 'desde \K[^ ]+')
            local ip=$(echo "$addr" | cut -d: -f1)
            
            if is_client_connection "$ip"; then
                local port=$(echo "$addr" | cut -d: -f2)
                unset active_connections["$addr"]
                if [[ ${port_connections_count[$port]} -gt 0 ]]; then
                    ((port_connections_count[$port]--))
                fi
            fi
        fi
    }

    # Función para mostrar la tabla de conexiones
    show_connections_table() {
        echo -e "\n${BLUE}Conexiones de clientes activas:${NC}"
        echo "╔════════════════════╦═══════════╦══════════════════╗"
        echo "║     IP Cliente     ║  Puerto   ║ Tiempo Conectado ║"
        echo "╠════════════════════╬═══════════╬══════════════════╣"
        
        local now=$(date +%s)
        if [ ${#active_connections[@]} -eq 0 ]; then
            printf "║%-62s║\n" "                   No hay conexiones activas                    "
        else
            for addr in "${!active_connections[@]}"; do
                local ip=$(clean_address "$(echo "$addr" | cut -d: -f1)")
                local port=$(clean_address "$(echo "$addr" | cut -d: -f2)")
                local timestamp="${active_connections[$addr]}"
                
                local conn_time=$(date -d "$timestamp" +%s)
                local duration=$((now - conn_time))
                local duration_str=$(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60)))
                
                printf "║ %-18s ║ %-9s ║ %-16s ║\n" "$ip" "$port" "$duration_str"
            done
        fi
        
        echo "╚════════════════════╩═══════════╩══════════════════╝"
        echo -e "\n${GREEN}Total de conexiones de clientes activas: ${#active_connections[@]}${NC}"
    }

    # Verificar si el servicio está activo
    if ! systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${RED}El servicio WebSocket no está activo.${NC}"
        return 1
    fi

    # Verificar si existe el archivo de log
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${RED}No se encuentra el archivo de log: $LOG_FILE${NC}"
        return 1
    fi

    # Inicializar el monitor
    show_header || return 1

    # Cargar conexiones existentes iniciales
    while read -r line; do
        process_log_line "$line"
    done < <(tail -n 1000 "$LOG_FILE")
    
    show_connections_table

    # Usar coproc para tail -f
    coproc LOGGER { tail -f "$LOG_FILE"; }

    # Bucle principal
    while true; do
        # Configurar lectura no bloqueante
        read -t 0.1 -n 1 key
        if [[ "$key" == "0" ]]; then
            kill $LOGGER_PID 2>/dev/null
            echo -e "\n${GREEN}Saliendo del monitor...${NC}"
            break
        fi

        # Leer y procesar logs si hay disponibles
        if read -t 0.1 -u ${LOGGER[0]} line; then
            process_log_line "$line"
            show_header
            show_connections_table
        fi
    done

    # Limpiar
    kill $LOGGER_PID 2>/dev/null
    wait $LOGGER_PID 2>/dev/null
    return 0
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

# Función principal mejorada
main() {
    # Verificar que se ejecute como root
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}Este script necesita privilegios de superusuario.${NC}"
        exec sudo "$0" "$@"
    fi

    # Verificar requisitos del sistema
    check_system_requirements

    while true; do
        echo -e "\n${BLUE}=== Gestión de Proxy WebSocket ===${NC}"
        echo "1. Abrir puerto WebSocket"
        echo "2. Cerrar puerto WebSocket"
        echo "3. Actualizar scripts"
        echo "4. Ver puertos abiertos"
        echo "5. Ver logs de conexiones"
        echo "6. Ver estadísticas"
        echo "7. Verificar actualizaciones"
        echo "8. Desinstalar"
        echo "9. Salir"
        
        read -p "Seleccione una opción: " choice

        case $choice in
            1) open_port ;;
            2) close_port ;;
            3) update_script ;;
            4) view_open_ports ;;
            5) view_logs ;;
            6) show_statistics ;;
            7) check_updates ;;
            8) uninstall_script ;;
            9) 
                echo -e "${GREEN}¡Hasta luego!${NC}"
                exit 0 
                ;;
            *)
                echo -e "${RED}Opción inválida${NC}"
                ;;
        esac

        echo -e "\nPresione Enter para continuar..."
        read -r
    done
}

# Manejo de señales
trap 'echo -e "\n${RED}Operación cancelada por el usuario.${NC}"; exit 1' SIGINT SIGTERM

# Iniciar el script
main "$@"
