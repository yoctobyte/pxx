# SPDX-License-Identifier: 0BSD
# Host side of tools/esp_qemu_mpy_net.sh: a minimal MQTT 3.1.1 broker (TCP) and
# an NTP server (UDP), each on a port the kernel picks. Prints
# `ready <mqtt-port> <ntp-port>`, then one line per packet it sees, so the
# broker's log is the record of what the chip actually sent.
#
# MQTT: acks CONNECT, PUBLISH at qos 1, SUBSCRIBE (then delivers one message,
# b"from-broker", on the subscribed topic) and PINGREQ; logs DISCONNECT. One
# client at a time, as many as connect.
# NTP: answers any 48-byte query with a fixed transmit timestamp, NTP_TS, so
# the chip's ntptime.time() has a known answer: NTP_TS - 2208988800 on a 1970
# epoch (pxx), NTP_TS - 3155673600 on MicroPython's 2000 one.
import select, socket, sys

NTP_TS = 3913056000 + 12345      # 2024-01-01 03:25:45 UTC, past ntptime's MIN_NTP_TIMESTAMP

def rd(c, n):
    b = b""
    while len(b) < n:
        x = c.recv(n - len(b))
        if not x:
            raise EOFError
        b += x
    return b

def serve_client(c):
    try:
        while True:
            h = rd(c, 1)[0]
            ln = 0; sh = 0
            while True:
                d = rd(c, 1)[0]; ln |= (d & 0x7F) << sh; sh += 7
                if not d & 0x80:
                    break
            body = rd(c, ln)
            t = h >> 4
            if t == 1:
                n = body[10] << 8 | body[11]
                print("CONNECT client", body[12:12 + n].decode(errors="replace"), flush=True)
                c.sendall(b"\x20\x02\x00\x00")
            elif t == 3:
                tl = body[0] << 8 | body[1]; topic = body[2:2 + tl]; rest = body[2 + tl:]
                qos = (h >> 1) & 3
                if qos:
                    pid = rest[:2]; rest = rest[2:]; c.sendall(b"\x40\x02" + pid)
                print("PUBLISH qos", qos, topic, rest, flush=True)
            elif t == 8:
                pid = body[:2]; tl = body[2] << 8 | body[3]; topic = body[4:4 + tl]
                print("SUBSCRIBE", topic, flush=True)
                c.sendall(b"\x90\x03" + pid + b"\x00")
                msg = b"from-broker"
                vh = bytes([0, len(topic)]) + topic
                c.sendall(bytes([0x30, len(vh) + len(msg)]) + vh + msg)
            elif t == 12:
                print("PINGREQ", flush=True); c.sendall(b"\xd0\x00")
            elif t == 14:
                print("DISCONNECT", flush=True); return
            else:
                print("packet type", t, body, flush=True)
    except (EOFError, ConnectionError):
        print("EOF", flush=True)

tcp = socket.socket(); tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
tcp.bind(("127.0.0.1", 0)); tcp.listen(4)
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); udp.bind(("127.0.0.1", 0))
print("ready", tcp.getsockname()[1], udp.getsockname()[1], flush=True)
while True:
    r, _, _ = select.select([tcp, udp], [], [])
    if udp in r:
        q, a = udp.recvfrom(512)
        if len(q) == 48:
            resp = bytearray(48)
            resp[0] = 0x24; resp[1] = 1        # server mode, stratum 1
            resp[40:44] = NTP_TS.to_bytes(4, "big")
            udp.sendto(bytes(resp), a)
            print("NTP query answered", flush=True)
    if tcp in r:
        c, _ = tcp.accept()
        serve_client(c)
        c.close()
