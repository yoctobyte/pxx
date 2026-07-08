/* ENet probe (game-library ladder): unity-build the library core and
   initialize/deinitialize. First rung only — no sockets exercised yet. */
#include "callbacks.c"
#include "compress.c"
#include "host.c"
#include "list.c"
#include "packet.c"
#include "peer.c"
#include "protocol.c"
#include "unix.c"

int main(void) {
    if (enet_initialize() != 0) return 1;
    ENetAddress addr;
    if (enet_address_set_host_ip(&addr, "127.0.0.1") != 0) { enet_deinitialize(); return 2; }
    enet_deinitialize();
    return 42;
}
