"""rtype.py TEXT [secs]: type TEXT into the ReactOS VM through qemu sendkey,
then (with secs) wait and save a screenshot to $PXX_ROS_DIR/snap/live.png.

Backslash escapes work (\\n is Enter); {key} passes a qemu key name through,
for example {ctrl-esc} (Start menu) or {ret}. US keyboard layout.
Start menu, Run...: rtype.py '{ctrl-esc}{up}{up}{ret}', then 'cmd\\n'.
"""
import os
import socket
import sys
import time

W = os.path.join(os.environ.get('PXX_ROS_DIR', '/data/vm/reactos'), 'snap')
names = {' ': 'spc', '\n': 'ret', '.': 'dot', ',': 'comma', '/': 'slash', '\\': 'backslash', '-': 'minus',
         '=': 'equal', ';': 'semicolon', "'": 'apostrophe', '[': 'bracket_left', ']': 'bracket_right',
         '`': 'grave_accent'}
shifted = {':': 'semicolon', '>': 'dot', '<': 'comma', '"': 'apostrophe', '%': '5', '(': '9', ')': '0',
           '_': 'minus', '+': 'equal', '*': '8', '&': '7', '|': 'backslash', '!': '1', '?': 'slash',
           '@': '2', '$': '4', '^': '6', '#': '3'}
s = socket.socket(socket.AF_UNIX)
s.connect(W + '/mon.sock')
time.sleep(0.3)
s.recv(65536)


def send(c):
    s.send((c + '\n').encode())
    time.sleep(0.12)


text = sys.argv[1].encode().decode('unicode_escape')
i = 0
while i < len(text):
    if text[i] == '{':
        j = text.index('}', i)
        send('sendkey ' + text[i + 1:j])
        i = j + 1
        time.sleep(0.5)
        continue
    c = text[i]
    if c.isalpha() and c.isupper():
        send('sendkey shift-' + c.lower())
    elif c.isalnum():
        send('sendkey ' + c)
    elif c in names:
        send('sendkey ' + names[c])
    elif c in shifted:
        send('sendkey shift-' + shifted[c])
    i += 1
if len(sys.argv) > 2:
    time.sleep(float(sys.argv[2]))
    send('screendump %s/live.ppm' % W)
    time.sleep(1)
    from PIL import Image
    Image.open(W + '/live.ppm').save(W + '/live.png')
    print(W + '/live.png')
s.close()
