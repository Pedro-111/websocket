#!/usr/bin/env python3
# encoding: utf-8
import socket
import threading
import select
import sys
import time
import os
import logging
import ssl
import subprocess
import base64
import argparse
from concurrent.futures import ThreadPoolExecutor
from typing import List, Set, Optional, Tuple, Dict
from dataclasses import dataclass
import configparser

active_connections = {}
connections_lock = threading.Lock()

# Mejora en la configuración de logging
logging.basicConfig(
    filename='/var/tmp/proxy.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(threadName)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

@dataclass
class Config:
    IP: str = '0.0.0.0'
    BUFLEN: int = 8196 * 8
    TIMEOUT: int = 60
    MSG: str = 'WSS'
    COR: str = '<font color="null">'
    FTAG: str = '</font>'
    DEFAULT_HOST: str = '0.0.0.0:22'
    MAX_WORKERS: int = 100
    CERTFILE: str = 'cert.pem'
    KEYFILE: str = 'key.pem'
    ACL: List[str] = None  # Lista de control de acceso
    BLOCKED_PAGES: List[str] = None  # Lista de páginas bloqueadas

    @property
    def RESPONSE(self) -> str:
        return f"HTTP/1.1 200 {self.COR}{self.MSG}{self.FTAG}\r\n\r\n"

# Cargar configuración desde un archivo
config_parser = configparser.ConfigParser()
config_parser.read('config.ini')

config = Config(
    ACL=config_parser.get('ACL', 'pages', fallback=None).split(',') if config_parser.has_option('ACL', 'pages') else None,
    BLOCKED_PAGES=config_parser.get('BlockedPages', 'pages', fallback=None).split(',') if config_parser.has_option('BlockedPages', 'pages') else None
)

def generate_ssl_certificates():
    """Genera certificados SSL si no existen"""
    if not os.path.exists(config.CERTFILE) or not os.path.exists(config.KEYFILE):
        logging.info("Generando certificados SSL...")
        try:
            subprocess.run([
                'openssl', 'req', '-x509', '-newkey', 'rsa:4096',
                '-keyout', config.KEYFILE, '-out', config.CERTFILE,
                '-days', '365', '-nodes', '-subj', '/CN=localhost'
            ], check=True)
            logging.info("Certificados SSL generados.")
        except subprocess.CalledProcessError as e:
            logging.error(f"Error generando certificados SSL: {e}")

class Server(threading.Thread):
    def __init__(self, host: str, port: int, use_ssl: bool = False, username: Optional[str] = None, password: Optional[str] = None):
        super().__init__()
        self.running: bool = False
        self.host: str = host
        self.port: int = port
        self.use_ssl: bool = use_ssl
        self.username: Optional[str] = username
        self.password: Optional[str] = password
        self.threads: Set = set()
        self.threadsLock: threading.Lock = threading.Lock()
        self.logLock: threading.Lock = threading.Lock()
        self.threadpool = ThreadPoolExecutor(max_workers=config.MAX_WORKERS)
        self.logger = logging.getLogger(f'Server-{port}')
        self.sockets = []  # Lista para mantener los sockets IPv4 e IPv6

    def setup_socket(self) -> List[tuple]:
        """Configura los sockets del servidor para IPv4 e IPv6"""
        sockets = []

        # Configurar socket IPv4
        try:
            soc_ipv4 = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            soc_ipv4.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            soc_ipv4.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            soc_ipv4.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            soc_ipv4.bind((self.host, self.port))
            soc_ipv4.listen(socket.SOMAXCONN)
            soc_ipv4.settimeout(2)

            if self.use_ssl:
                context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
                context.load_cert_chain(certfile=config.CERTFILE, keyfile=config.KEYFILE)
                soc_ipv4 = context.wrap_socket(soc_ipv4, server_side=True)

            sockets.append(('IPv4', soc_ipv4))
            self.logger.info(f"Socket IPv4 escuchando en puerto {self.port} {'con SSL' if self.use_ssl else ''}")
        except Exception as e:
            self.logger.error(f"Error configurando socket IPv4: {e}")

        # Configurar socket IPv6
        try:
            soc_ipv6 = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
            soc_ipv6.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            soc_ipv6.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            soc_ipv6.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            soc_ipv6.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            soc_ipv6.bind(('::', self.port))
            soc_ipv6.listen(socket.SOMAXCONN)
            soc_ipv6.settimeout(2)

            if self.use_ssl:
                context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
                context.load_cert_chain(certfile=config.CERTFILE, keyfile=config.KEYFILE)
                soc_ipv6 = context.wrap_socket(soc_ipv6, server_side=True)

            sockets.append(('IPv6', soc_ipv6))
            self.logger.info(f"Socket IPv6 escuchando en puerto {self.port} {'con SSL' if self.use_ssl else ''}")
        except Exception as e:
            self.logger.error(f"Error configurando socket IPv6: {e}")

        return sockets

    def run(self) -> None:
        try:
            self.sockets = self.setup_socket()

            if not self.sockets:
                self.logger.error("No se pudo crear ningún socket")
                return

            self.running = True

            while self.running:
                sockets_for_select = [s[1] for s in self.sockets]
                try:
                    readable, _, _ = select.select(sockets_for_select, [], [], 2)

                    for sock in readable:
                        try:
                            client, addr = sock.accept()
                            client.setblocking(True)
                            socket_type = 'IPv6' if ':' in str(addr[0]) else 'IPv4'
                            self.logger.info(f"Nueva conexión {socket_type} desde {addr}")
                            self.threadpool.submit(self.handle_connection, client, addr)
                        except socket.timeout:
                            continue
                        except Exception as e:
                            self.logger.error(f"Error en accept: {e}")
                except select.error as e:
                    self.logger.error(f"Error en select: {e}")
                    continue
                except Exception as e:
                    self.logger.error(f"Error inesperado: {e}")
                    continue

        except Exception as e:
            self.logger.error(f"Error en el servidor: {e}")
        finally:
            self.cleanup()

    def cleanup(self) -> None:
        """Limpieza de recursos"""
        self.running = False

        # Cerrar todos los sockets
        if hasattr(self, 'sockets'):
            for _, soc in self.sockets:
                try:
                    soc.close()
                except Exception as e:
                    self.logger.error(f"Error cerrando socket: {e}")

        # Limpiar conexiones
        with self.threadsLock:
            for conn in list(self.threads):
                try:
                    conn.close()
                except Exception as e:
                    self.logger.error(f"Error cerrando conexión: {e}")

        # Cerrar threadpool
        try:
            self.threadpool.shutdown(wait=True)
        except Exception as e:
            self.logger.error(f"Error cerrando threadpool: {e}")

    def handle_connection(self, client: socket.socket, addr: tuple) -> None:
        try:
            conn = ConnectionHandler(client, self, addr, self.username, self.password)
            self.add_conn(conn)
            conn.run()
        except Exception as e:
            self.log_message(f"Error handling connection from {addr}: {e}")
        finally:
            self.remove_conn(conn)

    def add_conn(self, conn: 'ConnectionHandler') -> None:
        with self.threadsLock:
            if self.running:
                self.threads.add(conn)

    def remove_conn(self, conn: 'ConnectionHandler') -> None:
        with self.threadsLock:
            self.threads.discard(conn)

    def log_message(self, message: str) -> None:
        with self.logLock:
            self.logger.info(message)

class ConnectionHandler:
    def __init__(self, client_socket: socket.socket, server: Server, addr: tuple, username: Optional[str], password: Optional[str]):
        self.client = client_socket
        self.server = server
        self.client_buffer = bytearray()
        self.target: Optional[socket.socket] = None
        self.client_addr = f"{addr[0]}:{addr[1]}"
        self.log = f'Conexión desde {self.client_addr}'
        self.connection_time = time.time()
        self.username = username
        self.password = password

    def close(self) -> None:
        """Cierra las conexiones de manera segura"""
        try:
            # Registrar desconexión en el log
            self.server.log_message(f"Cliente desconectado desde {self.client_addr}")

            for sock in (self.client, self.target):
                if sock:
                    try:
                        sock.shutdown(socket.SHUT_RDWR)
                        sock.close()
                    except Exception:
                        pass
        except Exception as e:
            self.server.log_message(f"Error al cerrar conexión de {self.client_addr}: {str(e)}")

    def run(self) -> None:
        try:
            if not self.handle_initial_connection():
                return

            self.server.log_message(f"Buffer recibido de {self.client_addr}: {self.client_buffer.decode('utf-8', errors='ignore')}")

            # Verificar autenticación básica si se proporcionaron credenciales
            if self.username and self.password:
                auth_header = self.get_header('Authorization')
                if not auth_header or not self.check_auth(auth_header):
                    self.client.send(b'HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm="Access to the staging site"\r\n\r\n')
                    return

            # Verificar ACL
            if config.ACL and self.client_addr.split(':')[0] not in config.ACL:
                self.client.send(b'HTTP/1.1 403 Forbidden\r\n\r\n')
                self.server.log_message(f"Conexión denegada desde {self.client_addr} (no en ACL)")
                return

            # Verificar páginas bloqueadas
            host = self.get_header('Host')
            if config.BLOCKED_PAGES and any(blocked in host for blocked in config.BLOCKED_PAGES):
                self.client.send(b'HTTP/1.1 403 Forbidden\r\n\r\n')
                self.server.log_message(f"Conexión denegada desde {self.client_addr} (página bloqueada: {host})")
                return

            # Intentamos obtener el host de diferentes fuentes
            self.host_port = (
                self.get_header('X-Real-Host') or
                self.get_connect_host() or
                self.get_header('Host') or
                config.DEFAULT_HOST
            )

            if not self.host_port:
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')
                return

            if not self.connect_and_tunnel(self.host_port):
                return

        except Exception as e:
            self.log += f' - error: {str(e)}'
            self.server.log_message(self.log)
        finally:
            self.close()

    def handle_initial_connection(self) -> bool:
        """Maneja la conexión inicial y lee el buffer del cliente"""
        try:
            self.client.settimeout(10)  # 10 seconds timeout
            data = self.client.recv(config.BUFLEN)

            if not data:
                self.server.log_message(f"No data received from {self.client_addr}")
                return False

            self.client_buffer = data
            return True
        except Exception as e:
            self.server.log_message(f"Error in initial connection: {e}")
            return False

    def get_headers(self) -> dict:
        """Obtiene los encabezados de la solicitud HTTP"""
        headers = {}
        try:
            raw_buffer = self.client_buffer.decode('utf-8', errors='replace')
            lines = [line.strip() for line in raw_buffer.replace('\r\n', '\n').split('\n') if line.strip()]
            for line in lines[1:]:
                if ': ' in line:
                    key, value = line.split(': ', 1)
                    headers[key.strip()] = value.strip()
            return headers
        except Exception as e:
            self.server.log_message(f"Error parsing headers: {e}")
            return {}

    def get_header(self, header: str) -> str:
        """Obtiene el valor de un header específico"""
        headers = self.get_headers()
        return headers.get(header, '')

    def get_connect_host(self) -> str:
        """Obtiene el host del método CONNECT"""
        try:
            request = self.client_buffer.decode('utf-8', errors='ignore')
            first_line = request.split('\r\n')[0]
            if first_line.startswith('CONNECT'):
                parts = first_line.split()
                if len(parts) >= 2:
                    return parts[1].split()[0]
            return ''
        except Exception:
            return ''

    def connect_and_tunnel(self, host_port: str) -> bool:
        """Establece la conexión y el túnel"""
        try:
            host_port = host_port.split()[0]
            self.connect_target(host_port)
            self.client.sendall(config.RESPONSE.encode())
            self.server.log_message(self.log + f' - CONNECT {host_port}')
            self.handle_tunnel()
            return True
        except Exception as e:
            self.log += f' - Error en conexión: {str(e)}'
            return False

    def connect_target(self, host: str) -> None:
        """Establece conexión con el objetivo"""
        host, port = self.parse_host_port(host)
        self.target = socket.create_connection((host, port), timeout=config.TIMEOUT)
        self.target.setblocking(True)

    @staticmethod
    def parse_host_port(host_port: str) -> tuple:
        """Parsea el host y puerto de la cadena de conexión"""
        if ':' in host_port:
            host, port = host_port.rsplit(':', 1)
            return host, int(port)
        return host_port, 22

    def handle_tunnel(self) -> None:
        """Maneja el túnel de datos entre cliente y objetivo"""
        try:
            while True:
                readable, _, exceptional = select.select(
                    [self.client, self.target],
                    [],
                    [self.client, self.target],
                    config.TIMEOUT
                )

                if exceptional:
                    self.server.log_message(f"Error en la conexión con {self.client_addr}")
                    break

                if not readable:  # Timeout
                    self.server.log_message(f"Timeout para {self.client_addr}")
                    break

                for sock in readable:
                    try:
                        data = sock.recv(config.BUFLEN)
                        if not data:
                            self.server.log_message(f"Conexión cerrada por {'cliente' if sock is self.client else 'destino'} {self.client_addr}")
                            return

                        if sock is self.target:
                            self.client.sendall(data)
                        else:
                            self.target.sendall(data)
                    except (ConnectionResetError, BrokenPipeError) as e:
                        self.server.log_message(f"Conexión interrumpida para {self.client_addr}: {str(e)}")
                        return
                    except Exception as e:
                        self.server.log_message(f"Error en el túnel para {self.client_addr}: {str(e)}")
                        return
        except Exception as e:
            self.server.log_message(f"Error en el manejo del túnel para {self.client_addr}: {str(e)}")
        finally:
            self.close()

    def check_auth(self, auth_header):
        try:
            auth_type, auth_string = auth_header.split()
            if auth_type.lower() == 'basic':
                auth_string = base64.b64decode(auth_string).decode('utf-8')
                username, password = auth_string.split(':')
                return username == self.username and password == self.password
        except Exception:
            return False
        return False

def main() -> None:
    """Función principal que inicia el servidor proxy"""
    parser = argparse.ArgumentParser(description='Inicia el servidor proxy con múltiples puertos y configuraciones de SSL opcionales.')
    parser.add_argument('ports', metavar='PORT', type=str, nargs='+', help='Lista de configuraciones de puertos en el formato PORT[:SSL][:USER:PASS]. Ejemplo: 8080 8443:ssl 9090:admin:secret')

    args = parser.parse_args()

    port_configs: List[Dict[str, Optional[str]]] = []

    for port_config in args.ports:
        parts = port_config.split(':')
        port = int(parts[0])
        use_ssl = 'ssl' in parts
        username = None
        password = None

        if len(parts) > 1:
            if parts[1] == 'ssl':
                use_ssl = True
                if len(parts) > 2:
                    username = parts[2]
                    if len(parts) > 3:
                        password = parts[3]
            else:
                username = parts[1]
                if len(parts) > 2:
                    password = parts[2]

        port_configs.append({
            'port': port,
            'use_ssl': use_ssl,
            'username': username,
            'password': password
        })

    try:
        # Generar certificados SSL si no existen
        generate_ssl_certificates()

        # Iniciar los servidores
        servers: List[Server] = []
        for port_config in port_configs:
            server = Server(config.IP, port_config['port'], port_config['use_ssl'], port_config['username'], port_config['password'])
            server.start()
            servers.append(server)
            logging.info(f"Servidor proxy iniciado en {config.IP}:{port_config['port']} {'con SSL' if port_config['use_ssl'] else ''}")

        # Wait for servers to finish (keeps main thread running)
        for server in servers:
            server.join()
    except KeyboardInterrupt:
        logging.info('Deteniendo servidores...')
        for server in servers:
            server.cleanup()

if __name__ == '__main__':
    main()
