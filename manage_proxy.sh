#!/bin/bash

PROXY_PATH="/usr/local/bin/proxy.py"
SERVICE_NAME="websocket-proxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Pedro-111/websocket/master/proxy.py"
LOG_FILE="/tmp/proxy.log"

download_proxy_script() {
    echo "Descargando la última versión de proxy.py..."
    sudo wget -O "$PROXY_PATH" "$GITHUB_RAW_URL"
    sudo chmod +x "$PROXY_PATH"
    echo "proxy.py actualizado."
}

create_service() {
    local port=$1
    cat << EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=WebSocket Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 $PROXY_PATH $port
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
    read -p "Ingrese el puerto para el WebSocket: " port
    download_proxy_script
    if [ -f "$SERVICE_FILE" ]; then
        sudo sed -i "s|ExecStart=.*|ExecStart=/usr/bin/python3 $PROXY_PATH $port|" "$SERVICE_FILE"
        sudo systemctl daemon-reload
        sudo systemctl restart $SERVICE_NAME
    else
        create_service $port
    fi
    echo "Puerto WebSocket $port abierto y servicio iniciado."
}

close_port() {
    if [ -f "$SERVICE_FILE" ]; then
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl disable $SERVICE_NAME
        sudo rm "$SERVICE_FILE"
        sudo systemctl daemon-reload
        echo "Servicio WebSocket detenido y deshabilitado."
    else
        echo "El servicio WebSocket no está instalado."
    fi
}

update_script() {
    download_proxy_script
    if systemctl is-active --quiet $SERVICE_NAME; then
        sudo systemctl restart $SERVICE_NAME
        echo "Servicio reiniciado con la nueva versión del script."
    else
        echo "Script actualizado. El servicio no estaba en ejecución."
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
    echo "Puertos WebSocket abiertos:"
    echo "------------------------"
    printf "%-10s %-20s %-10s\n" "Puerto" "Estado" "PID"
    echo "------------------------"
    sudo ss -tlnp | grep python3 | while read -r line; do
        port=$(echo $line | awk '{print $4}' | cut -d':' -f2)
        pid=$(echo $line | awk '{print $6}' | cut -d',' -f2 | cut -d'=' -f2)
        state="Activo"
        printf "%-10s %-20s %-10s\n" "$port" "$state" "$pid"
    done
}

view_logs() {
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
