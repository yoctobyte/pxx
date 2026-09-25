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

  MicroPython's NAMES, not its architecture: WLAN, AP_IF / STA_IF, active,
  config(essid=, password=, channel=), ifconfig. What differs, and why:
    * config() before active(True) is the only order: the settings are applied
      when the AP starts. Calling config() on a running AP restarts it with the
      new settings, which MicroPython also does in effect.
    * `ssid` is accepted as a spelling of `essid`, as newer MicroPython does.
    * STA_IF (joining another network) is REFUSED with OSError on active(True):
      it is not built, and a station that silently never connects is the
      worse answer. Tracked beside the owner's AP phone test.
    * status('stations') answers the number of associated stations; the other
      status() keys are not modelled.

  THE C HALF is lib/rtl/platform/esp/idf/pxx_esp (pxx_esp.c says why it is C:
  WIFI_INIT_CONFIG_DEFAULT). A project must add that component; without it the
  link fails naming pxx_wifi_ap_start, which is the refusal. }

interface

uses pylib, sysutils;

const
  STA_IF = 0;
  AP_IF  = 1;

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
      channel: Integer = 0; const ssid: AnsiString = '');
    function ifconfig: TPyList;
    function status(const param: AnsiString): Integer;
  end;

implementation

function pxx_wifi_ap_start(ssid, password: PChar; channel: Integer): Integer; external;
function pxx_wifi_ap_stop: Integer; external;
function pxx_wifi_ap_active: Integer; external;
function pxx_wifi_ap_ip(ip, mask, gw: Pointer): Integer; external;
function pxx_wifi_ap_stations: Integer; external;

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
  active := (FIf = AP_IF) and (pxx_wifi_ap_active <> 0);
end;

function WLAN.active(flag: Boolean): Boolean;
var rc: Integer;
begin
  if FIf = STA_IF then
  begin
    if flag then
      raise OSError.Create('network.WLAN(STA_IF): station mode is not built; only AP_IF is');
    active := False;
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
  channel: Integer; const ssid: AnsiString);
var restart: Boolean;
begin
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
var ip, mask, gw: LongWord; l: TPyList; v: Variant;
begin
  ip := 0; mask := 0; gw := 0;
  if FIf = AP_IF then pxx_wifi_ap_ip(@ip, @mask, @gw);
  l := TPyList.Create;
  v := IpText(ip);   l.append(v);
  v := IpText(mask); l.append(v);
  v := IpText(gw);   l.append(v);
  v := '0.0.0.0';    l.append(v);   { DNS: the AP serves none }
  ifconfig := pylist_mark_tuple(l);   { tuple(l) would COPY and strand l }
end;

function WLAN.status(const param: AnsiString): Integer;
begin
  if param = 'stations' then
  begin
    status := pxx_wifi_ap_stations;
    if status < 0 then status := 0;
  end
  else
    raise OSError.Create('network.WLAN.status: only ''stations'' is modelled');
end;

end.
