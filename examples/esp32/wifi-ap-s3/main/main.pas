{ SPDX-License-Identifier: 0BSD }
program Esp32S3WifiAp;
{ Wi-Fi access point + hello-world web page, ESP32-S3.

  Join the network from a phone, open http://192.168.4.1/ and the page is
  served by this program: a Pascal HTTP server over pxx's own PAL socket
  layer (lib/rtl/platform.pas, the ESP backend is lwIP). Only the Wi-Fi
  bring-up is C (main/wifi_ap.c, which says why).

  One connection at a time, request line logged to the serial console,
  every response closes the connection. }

uses platform;

const
  AP_SSID     = 'PXX-ESP32S3';
  AP_PASSWORD = 'pascal26';       { '' makes it an open network }
  AP_CHANNEL  = 6;
  HTTP_PORT   = 80;

procedure esp_rom_printf(fmt: PChar; v: Integer); external;
procedure esp_rom_prints(fmt: PChar; s: PChar); external name 'esp_rom_printf';
procedure vTaskDelay(ticks: Integer); external;
function esp_timer_get_time: Int64; external;
function esp_get_free_heap_size: LongWord; external;
function pxx_wifi_start_ap(ssid, password: PChar; channel: Integer): Integer; external;

var
  srv, cli, rc, requests: Integer;
  peerAddr: LongWord;
  peerPort: Integer;
  req: array[0..1023] of Char;
  n: Int64;
  line, path, peer, body, resp: AnsiString;

function IntStr(v: Int64): AnsiString;
var
  s: AnsiString;
  neg: Boolean;
begin
  if v = 0 then begin IntStr := '0'; Exit; end;
  neg := v < 0;
  if neg then v := -v;
  s := '';
  while v > 0 do
  begin
    s := Chr(Ord('0') + v mod 10) + s;
    v := v div 10;
  end;
  if neg then s := '-' + s;
  IntStr := s;
end;

function IpStr(a: LongWord): AnsiString;
begin
  IpStr := IntStr((a shr 24) and 255) + '.' + IntStr((a shr 16) and 255) + '.' +
           IntStr((a shr 8) and 255) + '.' + IntStr(a and 255);
end;

{ First line of the request, without the CR/LF. }
function RequestLine(len: Integer): AnsiString;
var
  i: Integer;
  s: AnsiString;
begin
  s := '';
  i := 0;
  while (i < len) and (req[i] <> #13) and (req[i] <> #10) do
  begin
    s := s + req[i];
    i := i + 1;
  end;
  RequestLine := s;
end;

{ 'GET /foo HTTP/1.1' -> '/foo' }
function RequestPath(const l: AnsiString): AnsiString;
var
  i: Integer;
  s: AnsiString;
begin
  s := '';
  i := 1;
  while (i <= Length(l)) and (l[i] <> ' ') do i := i + 1;
  i := i + 1;
  while (i <= Length(l)) and (l[i] <> ' ') do
  begin
    s := s + l[i];
    i := i + 1;
  end;
  RequestPath := s;
end;

function Page: AnsiString;
var
  up: Int64;
begin
  up := esp_timer_get_time div 1000000;
  Page :=
    '<!DOCTYPE html><html><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1">' +
    '<title>PXX on ESP32-S3</title>' +
    '<style>body{font-family:system-ui,sans-serif;margin:2em;background:#10141c;color:#e8ecf2}' +
    'h1{color:#7cc4ff}td{padding:.2em 1em .2em 0}code{color:#ffd479}</style></head><body>' +
    '<h1>Hello, world!</h1>' +
    '<p>This page was served by a <b>Pascal</b> program compiled by <b>pxx</b>, ' +
    'running on an ESP32-S3 &mdash; its own Wi-Fi access point and HTTP server.</p>' +
    '<table>' +
    '<tr><td>uptime</td><td><code>' + IntStr(up) + ' s</code></td></tr>' +
    '<tr><td>request</td><td><code>#' + IntStr(requests) + '</code></td></tr>' +
    '<tr><td>free heap</td><td><code>' + IntStr(esp_get_free_heap_size) + ' bytes</code></td></tr>' +
    '<tr><td>your address</td><td><code>' + peer + '</code></td></tr>' +
    '</table><p><a href="/" style="color:#7cc4ff">reload</a></p></body></html>';
end;

procedure Reply(const status, ctype, content: AnsiString);
begin
  resp := 'HTTP/1.1 ' + status + #13#10 +
          'Content-Type: ' + ctype + #13#10 +
          'Content-Length: ' + IntStr(Length(content)) + #13#10 +
          'Cache-Control: no-store' + #13#10 +
          'Connection: close' + #13#10#13#10 + content;
  PalSend(cli, @resp[1], Length(resp));
end;

begin
  esp_rom_prints('PXX wifi-ap: starting access point "%s"'#10, AP_SSID);
  rc := pxx_wifi_start_ap(AP_SSID, AP_PASSWORD, AP_CHANNEL);
  if rc <> 0 then
  begin
    esp_rom_printf('PXX wifi-ap: Wi-Fi bring-up FAILED, esp_err=0x%x'#10, rc);
    while True do vTaskDelay(1000);
  end;
  esp_rom_printf('PXX wifi-ap: AP up on channel %d, open http://192.168.4.1/'#10, AP_CHANNEL);

  srv := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  PalSetSocketReuseAddr(srv, 1);
  if (srv < 0) or (PalBindIpv4(srv, PAL_NET_IP_ANY, HTTP_PORT) < 0)
     or (PalListen(srv, 4) < 0) then
  begin
    esp_rom_printf('PXX wifi-ap: cannot listen on port %d'#10, HTTP_PORT);
    while True do vTaskDelay(1000);
  end;
  esp_rom_printf('PXX wifi-ap: HTTP server listening on port %d'#10, HTTP_PORT);

  requests := 0;
  while True do
  begin
    peerAddr := 0;
    peerPort := 0;
    cli := PalAcceptIpv4(srv, peerAddr, peerPort);
    if cli < 0 then
    begin
      vTaskDelay(10);
      Continue;
    end;
    peer := IpStr(peerAddr);
    n := PalRecv(cli, @req[0], SizeOf(req));
    if n > 0 then
    begin
      line := RequestLine(n);
      path := RequestPath(line);
      requests := requests + 1;
      esp_rom_prints('PXX wifi-ap: %s', PChar(peer));
      esp_rom_prints(' "%s"'#10, PChar(line));
      if path = '/' then
        Reply('200 OK', 'text/html; charset=utf-8', Page)
      else
        Reply('404 Not Found', 'text/plain', 'not found: ' + path + #10);
    end;
    PalSocketClose(cli);
  end;
end.
