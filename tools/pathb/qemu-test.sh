#!/bin/sh
# Boot a Linux kernel (with fbdev, e.g. bochs DRM, and devtmpfs) with an
# initramfs of busybox + the Path B bundle, run startx-pixx from a shell
# /init, then drive it over QMP and take a screendump. With /dev/dri/card0
# startx-pixx runs Xorg, whose log is copied to the serial log.
#   qemu-test.sh KERNEL OUT.png
# Env: BUNDLE (default $PATHB_WORK/bundle/pixx-pathb-desktop-x86_64.tar.gz),
#      BUSYBOX (a static busybox; default /usr/bin/busybox),
#      KEYS   text to type ("\n" = Enter),
#      COMBOS key chords, qcodes joined by + ("alt+shift+ret"),
#      MOVES  relative pointer moves "dx,dy dx,dy ..." (TinyX validates the
#             protocol on the first packets: send a dozen or more),
#      SETTLE seconds to wait after the server is up (default 8),
#      HOLD   seconds to keep QEMU up after the screendump (default 1; 20 or
#             more for the dmesg dump, 42 s after boot),
#      EXTRA  host files copied into the image's /usr/bin (static programs),
#      PROBE  a command run with DISPLAY=:0 once the server is up, its
#             output to the serial log ("=== probe").
#      SERIAL a file to copy the serial log to.
set -e
K=${1:?kernel}; OUT=${2:?out.png}
BUNDLE=${BUNDLE:-${PATHB_WORK:?}/bundle/pixx-pathb-desktop-x86_64.tar.gz}
BUSYBOX=${BUSYBOX:-/usr/bin/busybox}
D=$(mktemp -d)
R=$D/root
mkdir -p $R/bin $R/proc $R/sys $R/dev $R/root $R/etc
tar -xzf $BUNDLE -C $R
cp $BUSYBOX $R/bin/busybox
for f in ${EXTRA:-}; do cp "$f" $R/usr/bin/; done
printf '%s\n' "${PROBE:-}" > $R/etc/qx-probe
for t in sh mount mkdir chmod grep sleep kill cat ls echo uname wait dmesg tail od; do ln -sf busybox $R/bin/$t; done
echo "root:x:0:0:root:/root:/bin/sh" > $R/etc/passwd
echo "root:x:0:" > $R/etc/group
cat > $R/init <<'EOF'
#!/bin/sh
mount -t proc proc /proc; mount -t sysfs sysfs /sys; mount -t devtmpfs devtmpfs /dev
export PATH=/usr/bin:/bin
i=0; while [ ! -c /dev/fb0 ] && [ ! -c /dev/dri/card0 ] && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
sleep 3   # psmouse registers late
ls /dev/dri /dev/fb0 2>&1
echo "QX ready"
# Xorg logs to a file: copy it to the console once it has started
# and, once the keys and moves have been sent, the kernel's log (a client's
# segfault is there, not on its stderr)
( sleep 12; [ -f /tmp/Xorg.0.log ] && { echo "=== Xorg.0.log"; cat /tmp/Xorg.0.log; }
  if [ -n "$(cat /etc/qx-probe)" ]; then echo "=== probe"; DISPLAY=:0 sh /etc/qx-probe; fi
  sleep 30; echo "=== dmesg"; dmesg | tail -25 ) > /dev/ttyS0 2>&1 &
exec startx-pixx > /dev/ttyS0 2>&1
EOF
chmod +x $R/init
(cd $R && find . | cpio -o -H newc 2>/dev/null | gzip -1) > $D/initrd.gz
qemu-system-x86_64 -enable-kvm -m 1024 -vga std -display none -no-reboot \
  -kernel $K -initrd $D/initrd.gz -append "console=ttyS0 rdinit=/init quiet" \
  -serial file:$D/serial.log -qmp unix:$D/qmp,server=on,wait=off &
QP=$!
i=0; until grep -q 'QX ready' $D/serial.log 2>/dev/null || [ $i -ge 90 ]; do sleep 1; i=$((i+1)); done
sleep ${SETTLE:-8}
python3 -I - $D/qmp $D/shot.ppm <<'PY' || true
import socket, sys, json, time, os
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile('rw')
f.readline()
def cmd(c):
    f.write(json.dumps(c) + "\n"); f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r: return r
cmd({"execute": "qmp_capabilities"})
names = {" ": "spc", "\n": "ret", "-": "minus", ".": "dot", "/": "slash"}
for ch in os.environ.get("KEYS", "").replace("\\n", "\n"):
    k = names.get(ch, ch.lower() if ch.isalnum() else None)
    if k is None: continue
    keys = [{"type": "qcode", "data": k}]
    if ch.isupper(): keys.insert(0, {"type": "qcode", "data": "shift"})
    cmd({"execute": "send-key", "arguments": {"keys": keys}}); time.sleep(0.05)
for c in os.environ.get("COMBOS", "").split():
    cmd({"execute": "send-key", "arguments": {"keys": [{"type": "qcode", "data": k} for k in c.split("+")]}})
    time.sleep(1.5)
for mv in os.environ.get("MOVES", "").split():
    dx, dy = (int(v) for v in mv.split(","))
    cmd({"execute": "input-send-event", "arguments": {"events": [
        {"type": "rel", "data": {"axis": "x", "value": dx}},
        {"type": "rel", "data": {"axis": "y", "value": dy}}]}})
    time.sleep(0.2)
time.sleep(1.5)
cmd({"execute": "screendump", "arguments": {"filename": sys.argv[2]}})
PY
sleep ${HOLD:-1}   # HOLD: keep QEMU up for the late dmesg dump (42 s after boot)
kill $QP 2>/dev/null; wait $QP 2>/dev/null || true
[ -z "${SERIAL:-}" ] || cp $D/serial.log "$SERIAL"
python3 -c "from PIL import Image; Image.open('$D/shot.ppm').save('$OUT')"
grep -av '^\[' $D/serial.log | tail -${TAIL:-5}
