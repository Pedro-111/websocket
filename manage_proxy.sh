#!/bin/bash

PROXY_PATH="/usr/local/bin/proxy.py"
SERVICE_NAME="websocket-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/master/proxy.py"

download_proxy_script() {
    echo "Descargando la última versión de proxy.py..."
    sudo wget -O "$PROXY_PATH" "$GITHUB_RAW_URL"
    sudo chmod +x "$PROXY_PATH"
    echo "proxy.py actualizado."
}

create_service() {
    local ports=$1
    echo "Creando archivo de servicio con puertos: $ports"
    cat << EOF | sudo tee "$SERVICE_FILE"
[Unit]
Description=WebSocket Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 $PROXY_PATH $ports
Restart=on-failure
User=nobody
Group=nogroup

[Install]
WantedBy=multi-user.target
EOF

    echo "Archivo de servicio creado. Contenido:"
    sudo cat "$SERVICE_FILE"

    echo "Recargando daemon de systemd..."
    sudo systemctl daemon-reload
    echo "Habilitando servicio..."
    sudo systemctl enable $SERVICE_NAME
    echo "Iniciando servicio..."
    sudo systemctl start $SERVICE_NAME
    echo "Estado del servicio:"
    sudo systemctl status $SERVICE_NAME
}

open_port() {
    read -p "Ingrese los puertos para el WebSocket (separados por espacios): " new_ports
    
    if [ -f "$SERVICE_FILE" ]; then
        current_ports=$(sudo grep ExecStart "$SERVICE_FILE" | awk '{for(i=NF;i>0;i--) if($i ~ /^[0-9]+$/) print $i}')
        all_ports=$(echo "$current_ports $new_ports" | tr ' ' '\n' | sort -u | tr '\n' ' ')
        
        if [ "$all_ports" = "$current_ports" ]; then
            echo "No se han añadido nuevos puertos. Los puertos solicitados ya están en uso."
            return
        fi
        
        echo "Actualizando el archivo de servicio..."
        sudo sed -i "s|ExecStart=.*|ExecStart=/usr/bin/python3 $PROXY_PATH $all_ports|" "$SERVICE_FILE"
        echo "Archivo de servicio actualizado."
    else
        echo "Creando nuevo archivo de servicio..."
        create_service "$new_ports"
        echo "Archivo de servicio creado."
    fi
    
    echo "Recargando daemon de systemd..."
    sudo systemctl daemon-reload
    echo "Daemon recargado."

    echo "Reiniciando el servicio..."
    if sudo systemctl restart $SERVICE_NAME; then
        echo "Servicio reiniciado exitosamente."
    else
        echo "Error al reiniciar el servicio. Mostrando estado del servicio:"
        sudo systemctl status $SERVICE_NAME
    fi

    echo "Puertos WebSocket actualizados. Servicio reiniciado con los siguientes puertos: $all_ports"
}

close_port() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo "El servicio WebSocket no está instalado."
        return
    fi

    current_ports=$(sudo grep ExecStart "$SERVICE_FILE" | awk '{for(i=NF;i>0;i--) if($i ~ /^[0-9]+$/) print $i}')
    read -p "Ingrese el puerto a cerrar (o 'all' para cerrar todos): " port
    
    if [ "$port" != "all" ] && ! echo "$current_ports" | grep -q "$port"; then
    echo "El puerto $port no está en la configuración actual."
    return
    fi

    if [ "$port" == "all" ]; then
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl disable $SERVICE_NAME
        sudo rm "$SERVICE_FILE"
        sudo systemctl daemon-reload
        echo "Servicio WebSocket detenido y deshabilitado. Todos los puertos cerrados."
    else
        new_ports=$(echo $current_ports | tr ' ' '\n' | grep -v "^$port$" | tr '\n' ' ')
        new_ports=$(echo $new_ports | xargs)  # Elimina espacios extra
        if [ -z "$new_ports" ]; then
            sudo systemctl stop $SERVICE_NAME
            sudo systemctl disable $SERVICE_NAME
            sudo rm "$SERVICE_FILE"
            sudo systemctl daemon-reload
            echo "Último puerto cerrado. Servicio WebSocket detenido y deshabilitado."
        else
            sudo sed -i "s|ExecStart=.*|ExecStart=/usr/bin/python3 $PROXY_PATH $new_ports|" "$SERVICE_FILE"
            sudo systemctl daemon-reload
            sudo systemctl restart $SERVICE_NAME
            echo "Puerto $port cerrado. Servicio actualizado con los puertos restantes: $new_ports"
        fi
    fi
}

update_script() {
    # Actualizar proxy.py
    echo "Actualizando proxy.py..."
    sudo wget -O "$PROXY_PATH" "https://raw.githubusercontent.com/Pedro-111/websocket/master/proxy.py"
    sudo chmod +x "$PROXY_PATH"
    echo "proxy.py actualizado."

    # Actualizar manage_proxy.sh
    echo "Actualizando manage_proxy.sh..."
    TEMP_SCRIPT="/tmp/manage_proxy_temp.sh"
    wget -O "$TEMP_SCRIPT" "https://raw.githubusercontent.com/Pedro-111/websocket/master/manage_proxy.sh"
    
    if [ -f "$TEMP_SCRIPT" ]; then
        sudo mv "$TEMP_SCRIPT" "$0"
        sudo chmod +x "$0"
        echo "manage_proxy.sh actualizado."
        echo "Por favor, reinicie el script para aplicar los cambios."
        exit 0
    else
        echo "Error al actualizar manage_proxy.sh."
    fi

    # Reiniciar el servicio si está activo
    if systemctl is-active --quiet $SERVICE_NAME; then
        sudo systemctl restart $SERVICE_NAME
        echo "Servicio reiniciado con la nueva versión de los scripts."
    else
        echo "Scripts actualizados. El servicio no estaba en ejecución."
    fi
}

uninstall_script() {
    echo "Proceso de desinstalación iniciado."

    # Preguntar si se quiere parar el servicio de WebSocket
    if confirm "¿Desea detener el servicio de WebSocket?"; then
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl disable $SERVICE_NAME
        sudo rm -f $SERVICE_FILE
        sudo systemctl daemon-reload
        echo "Servicio de WebSocket detenido y eliminado."
    else
        echo "El servicio de WebSocket se mantendrá en ejecución."
    fi

    # Preguntar si se desea eliminar el script de gestión de proxy WebSocket
    if confirm "¿Desea eliminar el script de gestión de proxy WebSocket?"; then
        # Eliminar scripts
        sudo rm -f "$PROXY_PATH"
        sudo rm -f "$0"
        
        # Eliminar alias de proxy-manager
        sed -i '/alias proxy-manager=/d' "$HOME/.bashrc"
        
        echo "Scripts eliminados y alias removido."
        echo "Por favor, reinicie su terminal o ejecute 'source ~/.bashrc' para aplicar los cambios."
        echo "Proceso de desinstalación completado."
        exit 0
    else
        echo "Los scripts de gestión se mantendrán en su lugar."
    fi

    echo "Proceso de desinstalación completado."
}

# Función auxiliar para confirmar acciones
confirm() {
    while true; do
        read -p "$1 (s/n): " choice
        case "$choice" in
            [Ss]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Por favor, responda con 's' o 'n'.";;
        esac
    done
}

view_open_ports() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo "El servicio WebSocket no está instalado."
        return
    fi

    echo "Puertos WebSocket configurados:"
    echo "------------------------"
    printf "%-10s %-20s\n" "Puerto" "Estado"
    echo "------------------------"
    
    # Obtener los puertos desde el archivo de servicio
    current_ports=$(sudo grep ExecStart "$SERVICE_FILE" | awk '{for(i=NF;i>0;i--) if($i ~ /^[0-9]+$/) print $i}')
    
    # Obtener el estado del servicio
    service_status=$(systemctl is-active $SERVICE_NAME)
    
    if [ -z "$current_ports" ]; then
        echo "No se encontraron puertos configurados."
    else
        for port in $current_ports; do
            if [ "$service_status" = "active" ] && sudo netstat -tuln | grep -q ":$port "; then
                status="Activo"
            else
                status="Inactivo"
            fi
            printf "%-10s %-20s\n" "$port" "$status"
        done
    fi
    
    echo "------------------------"
    echo "Estado del servicio: $service_status"
}

view_logs() {
    LOG_FILE="/tmp/proxy.log"
    if [ -f "$LOG_FILE" ]; then
        echo "Últimas 20 líneas del log de conexiones:"
        echo "---------------------------------------"
        tail -n 20 "$LOG_FILE"
    else
        echo "El archivo de log no existe en $LOG_FILE"
    fi
}

while true; do
    echo "=== Gestión de Proxy WebSocket ==="
    echo "1. Abrir puerto WebSocket"
    echo "2. Cerrar puerto WebSocket"
    echo "3. Actualizar script"
    echo "4. Eliminar script"
    echo "5. Ver puertos abiertos"
    echo "6. Ver logs de conexiones"
    echo "7. Salir"
    read -p "Seleccione una opción: " choice

    case $choice in
        1) open_port ;;
        2) close_port ;;
        3) update_script ;;
        4) uninstall_script ;;
        5) view_open_ports ;;
        6) view_logs ;;
        7) exit 0 ;;
        *) echo "Opción inválida" ;;
    esac

    echo
done
