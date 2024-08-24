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

# Configuración de logging
logging.basicConfig(filename='/tmp/proxy.log', level=logging.INFO,
                    format='%(asctime)s - %(levelname)s - %(message)s')

# Configuración de conexión
IP = '0.0.0.0'
try:
    PORT = int(sys.argv[1])
except (IndexError, ValueError):
    PORT = 80
PASS = os.environ.get('PROXY_PASS', '')  # Obtener contraseña desde variable de entorno
BUFLEN = 8196 * 8
TIMEOUT = 60
MSG = 'WSS'
COR = '<font color="null">'
FTAG = '</font>'
DEFAULT_HOST = '0.0.0.0:22'
RESPONSE = f"HTTP/1.1 200 {COR}{MSG}{FTAG}\r\n\r\n"

class Server(threading.Thread):
    def __init__(self, host, port):
        super().__init__()
        self.running = False
        self.host = host
        self.port = port
        self.threads = set()
        self.threadsLock = threading.Lock()
        self.logLock = threading.Lock()
        self.threadpool = ThreadPoolExecutor(max_workers=100)  # Limitar conexiones simultáneas

    def run(self):
        self.soc = socket.socket(socket.AF_INET)
        self.soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.soc.settimeout(2)
        self.soc.bind((self.host, self.port))
        self.soc.listen(0)
        self.running = True

        try:
            while self.running:
                try:
                    c, addr = self.soc.accept()
                    c.setblocking(1)
                except socket.timeout:
                    continue
                
                self.threadpool.submit(self.handle_connection, c, addr)
        finally:
            self.running = False
            self.soc.close()
            
    def handle_connection(self, c, addr):
        conn = ConnectionHandler(c, self, addr)
        self.addConn(conn)
        conn.run()
        self.removeConn(conn)
            
    def printLog(self, log):
        logging.info(log)
    
    def addConn(self, conn):
        with self.threadsLock:
            if self.running:
                self.threads.add(conn)
                    
    def removeConn(self, conn):
        with self.threadsLock:
            self.threads.remove(conn)
                
    def close(self):
        self.running = False
        with self.threadsLock:
            for c in list(self.threads):
                c.close()
        self.threadpool.shutdown(wait=True)

class ConnectionHandler:
    def __init__(self, socClient, server, addr):
        self.clientClosed = False
        self.targetClosed = True
        self.client = socClient
        self.client_buffer = b''
        self.server = server
        self.log = f'Conexión: {addr}'

    def close(self):
        try:
            if not self.clientClosed:
                self.client.shutdown(socket.SHUT_RDWR)
                self.client.close()
        except:
            pass
        finally:
            self.clientClosed = True
            
        try:
            if not self.targetClosed:
                self.target.shutdown(socket.SHUT_RDWR)
                self.target.close()
        except:
            pass
        finally:
            self.targetClosed = True

    def run(self):
        try:
            self.client_buffer = self.client.recv(BUFLEN)
        
            hostPort = self.findHeader(self.client_buffer.decode(), 'X-Real-Host')
            
            if hostPort == '':
                hostPort = DEFAULT_HOST

            split = self.findHeader(self.client_buffer.decode(), 'X-Split')

            if split != '':
                self.client.recv(BUFLEN)
            
            if hostPort != '':
                passwd = self.findHeader(self.client_buffer.decode(), 'X-Pass')
                
                if len(PASS) != 0 and passwd == PASS:
                    self.method_CONNECT(hostPort)
                elif len(PASS) != 0 and passwd != PASS:
                    self.client.send(b'HTTP/1.1 400 WrongPass!\r\n\r\n')
                elif hostPort.startswith(IP):
                    self.method_CONNECT(hostPort)
                else:
                    self.client.send(b'HTTP/1.1 403 Forbidden!\r\n\r\n')
            else:
                logging.warning('- No X-Real-Host!')
                self.client.send(b'HTTP/1.1 400 NoXRealHost!\r\n\r\n')

        except Exception as e:
            self.log += f' - error: {str(e)}'
            self.server.printLog(self.log)
        finally:
            self.close()

    def findHeader(self, head, header):
        aux = head.find(f'{header}: ')
    
        if aux == -1:
            return ''

        aux = head.find(':', aux)
        head = head[aux+2:]
        aux = head.find('\r\n')

        if aux == -1:
            return ''

        return head[:aux]

    def connect_target(self, host):
        i = host.find(':')
        if i != -1:
            port = int(host[i+1:])
            host = host[:i]
        else:
            port = 443 if self.method == 'CONNECT' else 22

        (soc_family, soc_type, proto, _, address) = socket.getaddrinfo(host, port)[0]

        self.target = socket.socket(soc_family, soc_type, proto)
        self.targetClosed = False
        self.target.connect(address)

    def method_CONNECT(self, path):
        self.log += f' - CONNECT {path}'
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.client_buffer = b''
        self.server.printLog(self.log)
        self.doCONNECT()
                    
    def doCONNECT(self):
        socs = [self.client, self.target]
        count = 0
        error = False
        while True:
            count += 1
            recv, _, err = select.select(socs, [], socs, 3)
            if err:
                error = True
            if recv:
                for in_ in recv:
                    try:
                        data = in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target:
                                self.client.send(data)
                            else:
                                while data:
                                    byte = self.target.send(data)
                                    data = data[byte:]

                            count = 0
                        else:
                            break
                    except:
                        error = True
                        break
            if count == TIMEOUT:
                error = True

            if error:
                break

def main(host=IP, port=PORT):
    logging.info(f"Iniciando proxy en {host}:{port}")
    server = Server(host, port)
    server.start()
    try:
        while True:
            time.sleep(2)
    except KeyboardInterrupt:
        logging.info('Deteniendo el servidor...')
        server.close()

if __name__ == '__main__':
    main()
