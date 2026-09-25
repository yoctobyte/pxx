{ SPDX-License-Identifier: Zlib }
unit mimic_network;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ MicroPython's `network` module, the access-point half, for a NilPy program
  on an ESP32. `import network` resolves here through the mimic_ fallback, and
  only for an ESP build: this file lives in lib/rtl/platform/esp, which is on
  the unit path of an --platform=esp compile and of nothing else.

      import network
      ap = network.WLAN(network.AP_IF)
      ap.config(essid="PXX-NILPY", password="pascal26")
      ap.active(True)
      print(ap.ifconfig())     # ('192.168.4.1', '255.255.255.0', '192.168.4.1', '0.0.0.0')

      sta = network.WLAN(network.STA_IF)
      sta.active(True)
      for ssid, bssid, channel, rssi, auth, hidden in sta.scan(): ...
      sta.connect("home", "secret")
      while sta.status() == network.STAT_CONNECTING: time.sleep(0.25)
      if sta.isconnected(): print(sta.ifconfig())

  MicroPython's NAMES and, for the station, its BEHAVIOUR, taken from its
  source (ports/esp32/network_wlan.c, modnetwork.h): connect() returns at
  once and the driver keeps retrying (config(reconnects=n) bounds it, -1 is
  forever, the default); status() is STAT_GOT_IP, STAT_CONNECTING, STAT_IDLE
  or the IDF disconnect reason, and it REMEMBERS the last reason while
  retrying, so the loop above ends at STAT_NO_AP_FOUND for a network that is
  not there instead of spinning. AP and STA can be active together. What
  differs, and why:
    * AP settings are applied when the AP starts, so config() before
      active(True) is the natural order; config() on a running AP restarts it.
    * `ssid` is accepted as a spelling of `essid`, as newer MicroPython does.
    * status('stations') answers the NUMBER of associated stations, where
      MicroPython answers a list of them; status('rssi') is modelled.
    * connect(bssid=) and config('mac') & co. (the query form) are not.
    * Nothing is stored in flash: the credentials a program passes live only
      in RAM (MicroPython's port does the same).

  THE C HALF is lib/rtl/platform/esp/idf/pxx_esp (pxx_esp.c says why it is C:
  WIFI_INIT_CONFIG_DEFAULT). A project must add that component; without it the
  link fails naming pxx_wifi_ap_start, which is the refusal. }

interface

uses pylib, sysutils;

const
  STA_IF = 0;
  AP_IF  = 1;
  { status() -- MicroPython's values: the three STAT_ of its own
    (ports/esp32/modnetwork.h) and IDF's wifi_err_reason_t for the rest }
  STAT_IDLE          = 1000;
  STAT_CONNECTING    = 1001;
  STAT_GOT_IP        = 1010;
  STAT_BEACON_TIMEOUT = 200;
  STAT_NO_AP_FOUND   = 201;
  STAT_WRONG_PASSWORD = 202;
  STAT_ASSOC_FAIL    = 203;
  STAT_CONNECT_FAIL  = 203;
  STAT_HANDSHAKE_TIMEOUT = 204;
  STAT_NO_AP_FOUND_W_COMPATIBLE_SECURITY = 210;
  STAT_NO_AP_FOUND_IN_AUTHMODE_THRESHOLD = 211;
  STAT_NO_AP_FOUND_IN_RSSI_THRESHOLD = 212;
  { scan()'s authmode -- IDF's wifi_auth_mode_t, as MicroPython exports it }
  AUTH_OPEN          = 0;
  AUTH_WEP           = 1;
  AUTH_WPA_PSK       = 2;
  AUTH_WPA2_PSK      = 3;
  AUTH_WPA_WPA2_PSK  = 4;
  AUTH_WPA2_ENTERPRISE = 5;
  AUTH_WPA3_PSK      = 6;
  AUTH_WPA2_WPA3_PSK = 7;

type
  WLAN = class
  private
    FIf: Integer;
    FSsid, FPassword: AnsiString;
    FChannel: Integer;
  public
    constructor Create(interface_id: Integer = STA_IF);
    function active: Boolean; overload;
    function active(flag: Boolean): Boolean; overload;
    procedure config(const essid: AnsiString = ''; const password: AnsiString = #0;
      channel: Integer = 0; const ssid: AnsiString = ''; reconnects: Integer = -2);
    function ifconfig: TPyList;
    function status: Integer; overload;
    function status(const param: AnsiString): Integer; overload;
    function scan: TPyList;
    procedure connect(const ssid: AnsiString = ''; const key: AnsiString = '');
    procedure disconnect;
    function isconnected: Boolean;
  end;

implementation

function pxx_wifi_ap_start(ssid, password: PChar; channel: Integer): Integer; external;
function pxx_wifi_ap_stop: Integer; external;
function pxx_wifi_ap_active: Integer; external;
function pxx_wifi_ap_ip(ip, mask, gw: Pointer): Integer; external;
function pxx_wifi_ap_stations: Integer; external;
function pxx_wifi_sta_start: Integer; external;
function pxx_wifi_sta_stop: Integer; external;
function pxx_wifi_sta_active: Integer; external;
function pxx_wifi_sta_connect(ssid, password: PChar): Integer; external;
function pxx_wifi_sta_disconnect: Integer; external;
function pxx_wifi_sta_isconnected: Integer; external;
function pxx_wifi_sta_status: Integer; external;
procedure pxx_wifi_sta_set_reconnects(n: Integer); external;
function pxx_wifi_sta_ip(ip, mask, gw, dns: Pointer): Integer; external;
function pxx_wifi_sta_rssi(rssi: Pointer): Integer; external;
function pxx_wifi_scan: Integer; external;
function pxx_wifi_scan_get(i: Integer; ssid, bssid, channel, rssi, authmode: Pointer): Integer; external;

function IpText(a: LongWord): AnsiString;
begin
  IpText := IntToStr((a shr 24) and 255) + '.' + IntToStr((a shr 16) and 255) + '.' +
            IntToStr((a shr 8) and 255) + '.' + IntToStr(a and 255);
end;

procedure Refuse(const what: AnsiString; rc: Integer);
begin
  raise OSError.Create('network: ' + what + ' failed, esp_err_t 0x' + IntToHex(rc, 3));
end;

constructor WLAN.Create(interface_id: Integer);
begin
  if (interface_id <> STA_IF) and (interface_id <> AP_IF) then
    raise OSError.Create('network.WLAN: interface must be STA_IF or AP_IF');
  FIf := interface_id;
  FSsid := 'PXX-ESP32';
  FPassword := '';
  FChannel := 6;
end;

function WLAN.active: Boolean;
begin
  if FIf = AP_IF then active := pxx_wifi_ap_active <> 0
  else active := pxx_wifi_sta_active <> 0;
end;

function WLAN.active(flag: Boolean): Boolean;
var rc: Integer;
begin
  if FIf = STA_IF then
  begin
    if flag then rc := pxx_wifi_sta_start else rc := pxx_wifi_sta_stop;
    if rc <> 0 then Refuse('switching the station interface', rc);
    active := flag;
    Exit;
  end;
  if flag then
  begin
    rc := pxx_wifi_ap_start(PChar(FSsid), PChar(FPassword), FChannel);
    if rc <> 0 then Refuse('starting the access point', rc);
  end
  else
  begin
    rc := pxx_wifi_ap_stop;
    if rc <> 0 then Refuse('stopping the access point', rc);
  end;
  active := flag;
end;

procedure WLAN.config(const essid: AnsiString; const password: AnsiString;
  channel: Integer; const ssid: AnsiString; reconnects: Integer);
var restart: Boolean;
begin
  if reconnects <> -2 then
  begin
    if FIf <> STA_IF then
      raise OSError.Create('network.WLAN.config: reconnects is a STA_IF setting');
    if reconnects < -1 then
      raise ValueError.Create('network.WLAN.config: reconnects must be -1 or more');
    pxx_wifi_sta_set_reconnects(reconnects);
    Exit;
  end;
  if FIf = STA_IF then
    raise OSError.Create('network.WLAN(STA_IF).config: pass the network to connect()');
  if essid <> '' then FSsid := essid;
  if ssid <> '' then FSsid := ssid;
  if password <> #0 then FPassword := password;
  if channel > 0 then FChannel := channel;
  if (FPassword <> '') and (Length(FPassword) < 8) then
    raise OSError.Create('network: a WPA2 password needs at least 8 characters ('''' makes an open network)');
  restart := active;
  if restart then active(True);
end;

function WLAN.ifconfig: TPyList;
var ip, mask, gw, dns: LongWord; l: TPyList; v: Variant;
begin
  ip := 0; mask := 0; gw := 0; dns := 0;   { the AP serves no DNS }
  if FIf = AP_IF then pxx_wifi_ap_ip(@ip, @mask, @gw)
  else pxx_wifi_sta_ip(@ip, @mask, @gw, @dns);
  l := TPyList.Create;
  v := IpText(ip);   l.append(v);
  v := IpText(mask); l.append(v);
  v := IpText(gw);   l.append(v);
  v := IpText(dns);  l.append(v);
  ifconfig := pylist_mark_tuple(l);   { tuple(l) would COPY and strand l }
end;

function WLAN.status: Integer;
begin
  if FIf = STA_IF then status := pxx_wifi_sta_status
  else raise OSError.Create('network.WLAN(AP_IF).status: pass ''stations''');
end;

function WLAN.status(const param: AnsiString): Integer;
var rssi, rc: Integer;
begin
  if param = 'rssi' then
  begin
    if FIf <> STA_IF then raise OSError.Create('network.WLAN.status(''rssi''): STA_IF only');
    rssi := 0;
    rc := pxx_wifi_sta_rssi(@rssi);
    if rc <> 0 then Refuse('reading the RSSI (not connected?)', rc);
    status := rssi;
  end
  else if param = 'stations' then
  begin
    status := pxx_wifi_ap_stations;
    if status < 0 then status := 0;
  end
  else
    raise ValueError.Create('unknown status param');
end;

{ MicroPython's scan(): a list of (ssid, bssid, channel, RSSI, authmode,
  hidden) with ssid and bssid as bytes and hidden always False -- the ESP port
  scans with show_hidden and cannot tell, and says False. }
function WLAN.scan: TPyList;
var n, i, ch, rssi, auth, k: Integer; ssid: array[0..32] of Byte;
    bssid: array[0..5] of Byte; res, t: TPyList; b: TPyBytes; v: Variant;
begin
  if (FIf <> STA_IF) or (pxx_wifi_sta_active = 0) then
    raise OSError.Create('STA must be active');
  n := pxx_wifi_scan;
  if n < 0 then Refuse('scanning', -n);
  res := TPyList.Create;
  for i := 0 to n - 1 do
  begin
    if pxx_wifi_scan_get(i, @ssid[0], @bssid[0], @ch, @rssi, @auth) <> 0 then Break;
    t := TPyList.Create;
    k := 0;
    while (k < 32) and (ssid[k] <> 0) do k := k + 1;
    b := TPyBytes.Create(k);
    if k > 0 then Move(ssid[0], b.FData^, k);
    t.append(TObject(b));
    PXXObjRelease(Pointer(b));   { the tuple holds it now }
    b := TPyBytes.Create(6);
    Move(bssid[0], b.FData^, 6);
    t.append(TObject(b));
    PXXObjRelease(Pointer(b));
    v := ch;    t.append(v);
    v := rssi;  t.append(v);
    v := auth;  t.append(v);
    v := False; t.append(v);
    res.append(TObject(pylist_mark_tuple(t)));
  end;
  scan := res;
end;

procedure WLAN.connect(const ssid: AnsiString; const key: AnsiString);
var rc: Integer;
begin
  if FIf <> STA_IF then raise OSError.Create('network.WLAN.connect: STA_IF only');
  if pxx_wifi_sta_active = 0 then raise OSError.Create('STA must be active');
  rc := pxx_wifi_sta_connect(PChar(ssid), PChar(key));
  if rc <> 0 then Refuse('connecting', rc);
end;

procedure WLAN.disconnect;
var rc: Integer;
begin
  if FIf <> STA_IF then raise OSError.Create('network.WLAN.disconnect: STA_IF only');
  rc := pxx_wifi_sta_disconnect;
  if rc <> 0 then Refuse('disconnecting', rc);
end;

{ STA: has an address. AP: any station associated -- MicroPython's reading. }
function WLAN.isconnected: Boolean;
begin
  if FIf = STA_IF then isconnected := pxx_wifi_sta_isconnected <> 0
  else isconnected := pxx_wifi_ap_stations > 0;
end;

end.
