🌐 WebSocket Proxy Manager
Bienvenido al WebSocket Proxy Manager, un script en Bash que te permite gestionar fácilmente un proxy WebSocket. Con este script, puedes abrir y cerrar puertos, actualizar el proxy, eliminarlo y ver los logs de las conexiones, todo con unos simples comandos.
🚀 Características
- Abrir puerto WebSocket: Configura un puerto para el proxy WebSocket y habilita el servicio.
- Cerrar puerto WebSocket: Detén y desactiva el servicio del proxy.
- Actualizar script: Descarga la última versión de proxy.py y reinicia el servicio si está en ejecución.
- Eliminar script: Borra el script proxy.py y desinstala el servicio.
- Ver puertos abiertos: Muestra una lista de los puertos WebSocket actualmente activos.
- Ver logs de conexiones: Accede rápidamente a los últimos registros de conexiones.
🛠️ Requisitos
Sistema Operativo: Linux (Probado en distribuciones basadas en Debian)
Python: Asegúrate de tener Python 3 instalado en tu sistema.

```bash
sudo apt-get install python3
```
📥 Instalación
1. Clona el repositorio:

```bash
curl -sSL https://raw.githubusercontent.com/Pedro-111/websocket/master/install.sh | bash
```

2. Ejecuta el script de instalación:

Para instalar y configurar automáticamente el servicio:

```bash
sudo bash install.sh
```

Este script descargará manage_proxy.sh, y configurará los permisos necesarios.

3. Ejecuta el gestor de proxy:

```bash
sudo bash manage_proxy.sh
```

Sigue las instrucciones en pantalla para gestionar el proxy WebSocket.
📚 Cómo Usar
Una vez que el gestor está en marcha, verás un menú con opciones:

1. Abrir puerto WebSocket: Configura y abre un nuevo puerto para el proxy.
2. Cerrar puerto WebSocket: Detén el servicio en un puerto específico.
3. Actualizar script: Descarga la última versión de proxy.py.
4. Eliminar script: Desinstala el servicio y elimina el script.
5. Ver puertos abiertos: Muestra los puertos WebSocket actualmente activos.
6. Ver logs de conexiones: Revisa las últimas 20 líneas de los registros de conexiones.
7. Salir: Cierra el gestor.
👨‍💻 Contribuciones
Las contribuciones son bienvenidas. Si tienes mejoras, errores que corregir o nuevas características, no dudes en hacer un fork del repositorio y enviar un pull request.
📝 Licencia
Este proyecto está licenciado bajo la Licencia Pública General de GNU versión 3.0. Consulta el archivo LICENSE para más detalles.
---

¡Gracias por usar WebSocket Proxy Manager! Si tienes alguna pregunta o comentario, no dudes en abrir un issue en el repositorio. 🚀
