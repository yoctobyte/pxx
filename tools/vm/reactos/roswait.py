"""Wait on, or talk to, the ReactOS VM's qemu monitor.

roswait.py DIR STATE SECONDS   wait until the screen shows STATE, exit 1 on timeout
    wizard   the LiveCD language wizard (grey dialog body at 300,400)
    desktop  blue desktop at 300,400 and the grey taskbar at 400,590
    settle   just wait SECONDS
roswait.py DIR cmd 'MONITOR COMMAND'   run it, wait for the next (qemu) prompt,
    print the reply

DIR holds mon.sock (the snapshot directory). Needs PIL for the screen states.
"""
import socket
import sys
import time

d, state = sys.argv[1], sys.argv[2]


def conn():
    for _ in range(100):
        try:
            s = socket.socket(socket.AF_UNIX)
            s.connect(d + '/mon.sock')
            return s
        except OSError:
            time.sleep(0.3)
    sys.exit('no monitor')


def run(cmd, tmo=600):
    s = conn()
    s.settimeout(tmo)
    buf = b''
    while b'(qemu)' not in buf:
        buf += s.recv(65536)
    s.send((cmd + '\n').encode())
    buf = b''
    while b'(qemu)' not in buf:
        c = s.recv(65536)
        if not c:
            break
        buf += c
    s.close()
    return buf.decode('latin-1')


if state == 'cmd':
    print(run(sys.argv[3]).replace('\r', ''))
    sys.exit(0)
secs = float(sys.argv[3])
if state == 'settle':
    time.sleep(secs)
    sys.exit(0)
from PIL import Image  # noqa: E402


def grey(p):
    return abs(p[0] - p[1]) < 12 and abs(p[1] - p[2]) < 16 and p[0] > 180


def blue(p):
    return p[2] > 140 and p[0] < 100


end = time.time() + secs
while time.time() < end:
    time.sleep(5)
    try:
        run('screendump %s/w.ppm' % d, 30)
        im = Image.open(d + '/w.ppm').convert('RGB')
    except Exception:
        continue
    if im.size != (800, 600):
        continue
    mid, bar = im.getpixel((300, 400)), im.getpixel((400, 590))
    if state == 'wizard' and grey(mid):
        sys.exit(0)
    if state == 'desktop' and blue(mid) and grey(bar):
        sys.exit(0)
sys.exit(1)
