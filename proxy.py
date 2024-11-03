#!/usr/bin/env python3
# encoding: utf-8

import socket
import threading
import select
import sys
import time
import os
import logging
from concurrent.futures import ThreadPoolExecutor
from typing import List, Set, Optional
from dataclasses import dataclass

active_connections = {}
connections_lock = threading.Lock()
# Mejora en la configuración de logging
logging.basicConfig(
    filename='/tmp/proxy.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(threadName)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

@dataclass
class Config:
    IP: str = '0.0.0.0'
    PORT: int = 80
    PASS: str = os.environ.get('PROXY_PASS', '')
    BUFLEN: int = 8196 * 8
    TIMEOUT: int = 60
    MSG: str = 'WSS'
    COR: str = '<font color="null">'
    FTAG: str = '</font>'
    DEFAULT_HOST: str = '0.0.0.0:22'
    MAX_WORKERS: int = 100
    
    @property
    def RESPONSE(self) -> str:
        return f"HTTP/1.1 200 {self.COR}{self.MSG}{self.FTAG}\r\n\r\n"

config = Config()

class Server(threading.Thread):
    def __init__(self, host: str, port: int):
        super().__init__()
        self.running: bool = False
        self.host: str = host
        self.port: int = port
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
            soc_ipv4 = socket.socket(socket.AF_INET)
            soc_ipv4.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            soc_ipv4.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            soc_ipv4.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            soc_ipv4.bind((self.host, self.port))
            soc_ipv4.listen(socket.SOMAXCONN)
            soc_ipv4.settimeout(2)
            sockets.append(('IPv4', soc_ipv4))
            self.logger.info(f"Socket IPv4 escuchando en puerto {self.port}")
        except Exception as e:
            self.logger.error(f"Error configurando socket IPv4: {e}")

        # Configurar socket IPv6
        try:
            soc_ipv6 = socket.socket(socket.AF_INET6)
            soc_ipv6.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            soc_ipv6.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            soc_ipv6.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            soc_ipv6.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            soc_ipv6.bind(('::', self.port))
            soc_ipv6.listen(socket.SOMAXCONN)
            soc_ipv6.settimeout(2)
            sockets.append(('IPv6', soc_ipv6))
            self.logger.info(f"Socket IPv6 escuchando en puerto {self.port}")
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
        conn = ConnectionHandler(client, self, addr)
        self.add_conn(conn)
        try:
            conn.run()
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
    def __init__(self, client_socket: socket.socket, server: Server, addr: tuple):
        self.client = client_socket
        self.server = server
        self.client_buffer = bytearray()
        self.target: Optional[socket.socket] = None
        self.client_addr = f"{addr[0]}:{addr[1]}"
        self.log = f'Conexión desde {self.client_addr}'
        self.connection_time = time.time()
        
    def close(self) -> None:
        """Cierra las conexiones de manera segura"""
        # Registrar desconexión en el log
        self.server.log_message(f"Desconexión desde {self.client_addr}")
        
        for sock in (self.client, self.target):
            if sock:
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                    sock.close()
                except Exception:
                    pass

    def run(self) -> None:
        try:
            if not self.handle_initial_connection():
                return

            self.server.log_message(f"Buffer recibido de {self.client_addr}: {self.client_buffer.decode('utf-8', errors='ignore')}")
            
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

            if not self.authenticate_and_connect(self.host_port):
                return

        except Exception as e:
            self.log += f' - error: {str(e)}'
            self.server.log_message(self.log)
        finally:
            self.close()

    def handle_initial_connection(self) -> bool:
        """Maneja la conexión inicial y lee el buffer del cliente"""
        try:
            data = self.client.recv(config.BUFLEN)
            if not data:
                return False
            self.client_buffer = data
            return True
        except Exception as e:
            self.server.log_message(f"Error en conexión inicial: {e}")
            return False

    def get_header(self, header: str) -> str:
        """Obtiene el valor de un header específico"""
        try:
            headers = self.client_buffer.decode('utf-8', errors='ignore')
            for line in headers.split('\r\n'):
                if line.lower().startswith(f'{header.lower()}:'):
                    return line.split(':', 1)[1].strip()
            return ''
        except Exception as e:
            self.server.log_message(f"Error parsing header {header}: {e}")
            return ''

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

    def authenticate_and_connect(self, host_port: str) -> bool:
        """Autentica la conexión y establece el túnel"""
        try:
            host_port = host_port.split()[0]
            
            if config.PASS:
                if self.get_header('X-Pass') != config.PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                    return False

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
        while True:
            readable, _, exceptional = select.select(
                [self.client, self.target],
                [],
                [self.client, self.target],
                config.TIMEOUT
            )

            if exceptional:
                break

            for sock in readable:
                try:
                    data = sock.recv(config.BUFLEN)
                    if not data:
                        return
                    
                    if sock is self.target:
                        self.client.sendall(data)
                        with connections_lock:
                            active_connections[self.addr]['bytes_received'] += len(data)
                    else:
                        self.target.sendall(data)
                        with connections_lock:
                            active_connections[self.addr]['bytes_sent'] += len(data)
                except Exception:
                    return

def main() -> None:
    """Función principal que inicia el servidor proxy"""
    try:
        ports = [int(port) for port in sys.argv[1:]] or [config.PORT]
        servers: List[Server] = []

        for port in ports:
            server = Server(config.IP, port)
            server.start()
            servers.append(server)
            logging.info(f"Servidor proxy iniciado en {config.IP}:{port}")

        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        logging.info('Deteniendo servidores...')
        for server in servers:
            server.cleanup()

if __name__ == '__main__':
    main()
