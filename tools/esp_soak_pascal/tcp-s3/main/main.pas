{ SPDX-License-Identifier: 0BSD }
program Esp32TcpSoak;
{ Pascal (non-NilPy) TCP loopback client/server loop on ESP32-S3, PAL sockets.
  Each pass: wait ~1.5 s (2*MSL = 1 s: the previous pass's TIME_WAIT pcbs
  drain, so both heap reads see one pass's worth), then CONNS connections:
  connect, accept, 64 bytes each way, close both. Listener is set up once.

  Run: SOAK_SRC=tools/esp_soak_pascal SOAK_TIMEOUT=900 tools/esp_heap_soak.sh
  [--control] --passes 40 tcp-s3. Measured 2026-09-25 under QEMU: delta=0 over
  40 passes (320 connections, errs=0); --control 76 B/pass (64 + 12 header). }
uses platform;

procedure esp_rom_printf(fmt: string; v: Integer); external;
function esp_netif_init: Integer; external;
procedure vTaskDelay(ticks: Integer); external;

const
  PORT = 4242;
  CONNS = 8;

var
  lsn, cli, acc, i, j, rc: Integer;
  started: Boolean;
  errs, total: Integer;
  sbuf, rbuf: array[0..63] of Byte;
  n: Int64;

begin
  if not started then
  begin
    started := True;
    errs := 0; total := 0;
    rc := esp_netif_init;
    vTaskDelay(50);
    lsn := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
    rc := PalSetSocketReuseAddr(lsn, 1);
    if PalBindIpv4(lsn, PAL_NET_IP_LOOPBACK, PORT) < 0 then errs := errs + 1000;
    if PalListen(lsn, 4) < 0 then errs := errs + 1000;
    for j := 0 to 63 do sbuf[j] := j;
  end;
  for j := 1 to 150 do vTaskDelay(1);
  for i := 1 to CONNS do
  begin
    cli := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
    if cli < 0 then begin errs := errs + 1; continue; end;
    if PalConnectIpv4(cli, PAL_NET_IP_LOOPBACK, PORT) < 0 then errs := errs + 1;
    acc := PalAccept(lsn);
    if acc < 0 then errs := errs + 1
    else
    begin
      n := PalSend(cli, @sbuf[0], 64);
      if n <> 64 then errs := errs + 1;
      n := PalRecv(acc, @rbuf[0], 64);
      if (n <> 64) or (rbuf[63] <> 63) then errs := errs + 1;
      n := PalSend(acc, @rbuf[0], 64);
      n := PalRecv(cli, @rbuf[0], 64);
      if n <> 64 then errs := errs + 1;
      rc := PalSocketClose(acc);
    end;
    rc := PalSocketClose(cli);
    total := total + 1;
  end;
  esp_rom_printf('TCPSOAK conns=%d'#10, total);
  esp_rom_printf('TCPSOAK errs=%d'#10, errs);
end.
