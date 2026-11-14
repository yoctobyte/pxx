"""mon.py SOCK CMD [repeat [interval]]: send a qemu monitor command, optionally
repeated, without waiting for its reply (roswait.py cmd waits)."""
import socket
import sys
import time

sock, cmd = sys.argv[1], sys.argv[2]
rep = int(sys.argv[3]) if len(sys.argv) > 3 else 1
gap = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
for _ in range(50):
    try:
        s = socket.socket(socket.AF_UNIX)
        s.connect(sock)
        break
    except OSError:
        time.sleep(0.2)
else:
    sys.exit('no monitor at ' + sock)
time.sleep(0.3)
s.recv(4096)
for _ in range(rep):
    s.send((cmd + '\n').encode())
    time.sleep(gap)
time.sleep(0.5)
s.close()
