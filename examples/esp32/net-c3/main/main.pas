program Esp32NetSmoke;
{ PXX -> ESP-IDF lwIP socket smoke (ESP32-C3 / riscv32).

  Exercises the PAL socket surface on real ESP-IDF lwIP, over the 127.0.0.1 loop
  interface (LWIP_HAVE_LOOPIF, enabled by CONFIG_LWIP_NETIF_LOOPBACK) so it needs
  no Wi-Fi/Ethernet bring-up — only esp_netif_init to start the lwIP TCP/IP task.
  A UDP datagram is bound to a fixed loopback port, sent, polled for readiness,
  and received; the core result is folded into one status word.

  Uses the portable PAL (`platform`) directly rather than the net.pas facade:
  PAL is the cross-target layer, and net.pas's by-value TNetAddress helpers hit
  a riscv32 record-result codegen gap (feature-riscv32-record-function-results).
  The x86-64 host equivalent is test/lib_platform_net_udp.pas (same path, posix).

  Validated under qemu-system-riscv32 (Espressif fork): the core datagram path
  (socket/bind/sendto/poll/recvfrom + loopback delivery) passes ->
    PXX-net-smoke status=0
  Each core failure stage sets a distinct bit. The peer/getsockname address
  read-back is printed as a diagnostic, NOT gated: on ESP lwIP those return an
  unfilled (zero) sockaddr under qemu — see
  feature-pal-esp-lwip-sockaddr-readback. The send-side sockaddr layout (lwIP is
  BSD: sin_len@0, sin_family@1) is fixed and proven by the successful delivery. }

uses platform;

procedure esp_rom_printf(fmt: string; v: Integer); external;
function esp_netif_init: Integer; external;
procedure vTaskDelay(ticks: Integer); external;

const
  SMOKE_PORT = 3333;

var
  srv, cli: Integer;
  srvAddr, peerAddr: LongWord;
  srvBoundPort, peerPort: Integer;
  msg, buf: array[0..2] of Byte;
  n: Int64;
  pr, status, rc: Integer;

begin
  status := 0;
  msg[0] := Ord('u');
  msg[1] := Ord('d');
  msg[2] := Ord('p');

  { Start the lwIP TCP/IP task; the loop interface (127.0.0.1) comes up with it.
    No Wi-Fi/Ethernet needed for loopback traffic. }
  rc := esp_netif_init;
  if rc <> 0 then status := status or 1;
  vTaskDelay(50);

  srv := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if srv < 0 then status := status or 2;
  rc := PalSetSocketReuseAddr(srv, 1);
  rc := PalBindIpv4(srv, PAL_NET_IP_LOOPBACK, SMOKE_PORT);
  if rc < 0 then status := status or 2;
  { Nonblocking so a missing datagram cannot hang the smoke. }
  rc := PalSetSocketNonBlocking(srv, 1);

  cli := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_DGRAM, 0);
  if cli < 0 then status := status or 4;

  n := PalSendToIpv4(cli, @msg[0], 3, PAL_NET_IP_LOOPBACK, SMOKE_PORT);
  if n <> 3 then status := status or 8;

  pr := PalPoll(srv, PAL_POLL_IN, 1000);
  if (pr and PAL_POLL_IN) = 0 then status := status or 16;

  peerAddr := 0;
  peerPort := 0;
  n := PalRecvFromIpv4(srv, @buf[0], 3, peerAddr, peerPort);
  if (n <> 3) or (buf[0] <> msg[0]) or (buf[1] <> msg[1]) or (buf[2] <> msg[2]) then
    status := status or 32;

  { Diagnostics (not gated): address read-back from lwIP. }
  srvAddr := 0;
  srvBoundPort := 0;
  rc := PalGetSockNameIpv4(srv, srvAddr, srvBoundPort);
  esp_rom_printf('PXX-net diag getsockname-rc=%d'#10, rc);
  esp_rom_printf('PXX-net diag bound-port=%d'#10, srvBoundPort);
  esp_rom_printf('PXX-net diag peer-port=%d'#10, peerPort);

  rc := PalSocketClose(cli);
  rc := PalSocketClose(srv);

  esp_rom_printf('PXX-net-smoke status=%d'#10, status);

  { app_main has no returning epilogue yet; park so the WDT stays fed. }
  while True do
    vTaskDelay(1000);
end.
