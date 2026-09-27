# SPDX-License-Identifier: 0BSD
# A TLS front for a plain TCP server, for the QEMU TLS rows
# (tools/esp_qemu_urequests.sh --tls, tools/esp_qemu_mpy_net.sh --tls):
#
#   python3 tls_relay.py <cert.pem> <key.pem> <backend-port> [<backend-port> ...]
#
# For each backend port it listens on a port the kernel picks, terminates TLS
# with the given certificate (CPython's ssl defaults: TLS 1.2 and 1.3), and
# pipes the plaintext to 127.0.0.1:<backend-port> both ways until either side
# closes. Prints `ready <tls-port> ...` in the order the backends were given,
# then one `TLS <tls-port> <version> <cipher>` line per completed handshake, so
# the log records what the chip actually negotiated, and one `TLSFAIL ...` per
# handshake that did not complete (a CERT_REQUIRED client refusing us closes
# the connection mid-handshake, which is the verification row's evidence).
import socket, ssl, sys, threading


def pump(a, b):
    try:
        while True:
            d = a.recv(4096)
            if not d:
                break
            b.sendall(d)
    except OSError:
        pass
    for s in (a, b):
        try:
            s.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass


def serve(ctx, lsock, backend):
    port = lsock.getsockname()[1]
    while True:
        raw, _ = lsock.accept()
        try:
            t = ctx.wrap_socket(raw, server_side=True)
        except (ssl.SSLError, OSError) as e:
            print("TLSFAIL", port, type(e).__name__, str(e)[:120], flush=True)
            raw.close()
            continue
        print("TLS", port, t.version(), t.cipher()[0], flush=True)
        up = socket.create_connection(("127.0.0.1", backend))
        threading.Thread(target=pump, args=(t, up), daemon=True).start()
        threading.Thread(target=pump, args=(up, t), daemon=True).start()


def main():
    cert, key = sys.argv[1], sys.argv[2]
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(cert, key)
    ports = []
    for b in sys.argv[3:]:
        ls = socket.socket()
        ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        ls.bind(("0.0.0.0", 0))
        ls.listen(16)
        ports.append(str(ls.getsockname()[1]))
        threading.Thread(target=serve, args=(ctx, ls, int(b)), daemon=True).start()
    print("ready", " ".join(ports), flush=True)
    threading.Event().wait()


main()
