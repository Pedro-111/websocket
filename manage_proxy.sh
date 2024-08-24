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
    cat << EOF | sudo tee "$SERVICE_FILE" > /dev/null
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

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME
}

open_port() {
    read -p "Ingrese los puertos para el WebSocket (separados por espacios): " new_ports
    
    if [ -f "$SERVICE_FILE" ]; then
        # Si el servicio ya existe, añadimos los nuevos puertos
        current_ports=$(sudo systemctl show -p ExecStart --value $SERVICE_NAME | awk '{print substr($0, index($0,$3))}')
        all_ports="$current_ports $new_ports"
        sudo sed -i "s|ExecStart=.*|ExecStart=/usr/bin/python3 $PROXY_PATH $all_ports|" "$SERVICE_FILE"
        sudo systemctl daemon-reload
        sudo systemctl restart $SERVICE_NAME
    else
        # Si el servicio no existe, lo creamos con los nuevos puertos
        create_service "$new_ports"
    fi
    
    echo "Puertos WebSocket $new_ports abiertos y servicio iniciado/actualizado."
}

close_port() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo "El servicio WebSocket no está instalado."
        return
    fi

    current_ports=$(sudo systemctl show -p ExecStart --value $SERVICE_NAME | awk '{print $NF}')
    read -p "Ingrese el puerto a cerrar (o 'all' para cerrar todos): " port

    if [ "$port" == "all" ]; then
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl disable $SERVICE_NAME
        sudo rm "$SERVICE_FILE"
        sudo systemctl daemon-reload
        echo "Servicio WebSocket detenido y deshabilitado. Todos los puertos cerrados."
    else
        new_ports=$(echo $current_ports | sed "s/$port//g" | tr -s ' ')
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
            echo "Puerto $port cerrado. Servicio actualizado con los puertos restantes."
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

remove_script() {
    if [ -f "$PROXY_PATH" ]; then
        sudo rm "$PROXY_PATH"
        close_port
        echo "Script eliminado y servicio desinstalado."
    else
        echo "El script proxy.py no existe en $PROXY_PATH"
    fi
}

view_open_ports() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo "El servicio WebSocket no está instalado."
        return
    fi

    echo "Puertos WebSocket abiertos:"
    echo "------------------------"
    printf "%-10s %-20s\n" "Puerto" "Estado"
    echo "------------------------"
    
    current_ports=$(sudo systemctl show -p ExecStart --value $SERVICE_NAME | awk '{print $NF}')
    status=$(systemctl is-active $SERVICE_NAME)
    
    for port in $current_ports; do
        printf "%-10s %-20s\n" "$port" "$status"
    done
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
        4) remove_script ;;
        5) view_open_ports ;;
        6) view_logs ;;
        7) exit 0 ;;
        *) echo "Opción inválida" ;;
    esac

    echo
done
