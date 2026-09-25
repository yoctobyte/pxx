# SPDX-License-Identifier: 0BSD
# UDP (SOCK_DGRAM, sendto, recvfrom, recv with a timeout) and getaddrinfo, the
# socket surface MicroPython's ntptime and umqtt use. Expected is CPython 3.
import socket
ai = socket.getaddrinfo("127.0.0.1", 123)
print(ai[0][-1], ai[0][0] == socket.AF_INET)
print(socket.getaddrinfo("localhost", 80)[0][-1][1])
srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
srv.bind(("127.0.0.1", 0))
port = srv.getsockname()[1]
cli = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
cli.settimeout(1)
n = cli.sendto(b"ping", ("127.0.0.1", port))
print("sent", n)
data, addr = srv.recvfrom(64)
print(data, addr[0])
srv.sendto(data + b"!", addr)
print(cli.recv(64))
try:
    cli.recv(64)
except OSError as e:
    print("timeout:", type(e).__name__, e)
cli.close()
srv.close()
