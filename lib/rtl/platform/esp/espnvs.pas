{ SPDX-License-Identifier: Zlib }
unit espnvs;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ ESP32 settings that survive a reboot: key/value storage in the flash's NVS
  partition. For Pascal and for Nil Python; ints and strings in and out, so
  neither half needs the Python runtime.

      import 'espnvs.pas' as nvs
      boots = nvs.get_int("boots", 0) + 1
      nvs.set_int("boots", boots)
      nvs.set_str("name", "kitchen")
      nvs.commit()                  # nothing is durable until commit

  ONE NAMESPACE, "pxx", opened on first use. IDF namespaces keep libraries
  from colliding; a program talking to its own settings has no use for more
  than one, and a fixed name keeps every call a plain key/value pair.
  NvsOpenNamespace switches it for a program that shares the partition with
  C code of its own.

  COMMIT IS EXPLICIT, as it is in IDF: set_* writes can be batched and a
  power cut before commit loses them. The read side needs no commit.

  get_int / get_str take a DEFAULT and return it when the key is absent, so
  first boot needs no special case. Any other error also answers the default;
  last_error() says which, for a program that cares.

  Keys are at most 15 characters (IDF's limit); a longer one is refused with
  ESP_ERR_NVS_KEY_TOO_LONG. Strings are stored without their length limit
  being checked here: IDF refuses anything over ~4000 bytes.

  FIRST USE INITIALISES THE PARTITION. When nvs_flash_init reports no free
  pages or a newer format, the partition is erased and initialised again --
  IDF's own documented recovery, and what every IDF example does. That loses
  whatever was stored, which is the only way forward from either state.

  IDF-only. A project using this unit needs nvs_flash in its REQUIRES, and a
  partition table with an nvs partition (the IDF stock tables have one). }

interface

const
  NVS_ERR_NOT_FOUND    = $1102;
  NVS_ERR_KEY_TOO_LONG = $1109;

{ Pascal surface. Each Set/Commit/Erase returns the SDK's esp_err_t; 0 is ESP_OK. }
function NvsSetInt(const key: string; value: Int64): Integer;
function NvsGetInt(const key: string; fallback: Int64): Int64;
function NvsSetStr(const key, value: string): Integer;
function NvsGetStr(const key, fallback: string): string;
function NvsErase(const key: string): Integer;
function NvsCommit: Integer;
{ The esp_err_t of the last call, including a Get that answered its default. }
function NvsLastError: Integer;
{ Close the current namespace and use ns from now on (at most 15 characters). }
function NvsOpenNamespace(const ns: string): Integer;

{ ---- the Nil Python surface ---------------------------------------------- }
function set_int(key: string; value: Int64): Integer;
function get_int(key: string; fallback: Int64): Int64;
function set_str(key, value: string): Integer;
function get_str(key, fallback: string): string;
function erase(key: string): Integer;
function commit: Integer;
function last_error: Integer;

implementation

const
  NVS_READWRITE = 1;
  ESP_ERR_NVS_NO_FREE_PAGES = $110D;
  ESP_ERR_NVS_NEW_VERSION_FOUND = $1110;

function nvs_flash_init: Integer; cdecl; external;
function nvs_flash_erase: Integer; cdecl; external;
function nvs_open(ns: PChar; mode: Integer; out_handle: Pointer): Integer; cdecl; external;
procedure nvs_close(h: LongWord); cdecl; external;
function nvs_set_i64(h: LongWord; key: PChar; value: Int64): Integer; cdecl; external;
function nvs_get_i64(h: LongWord; key: PChar; out_value: Pointer): Integer; cdecl; external;
function nvs_set_str(h: LongWord; key: PChar; value: PChar): Integer; cdecl; external;
function nvs_get_str(h: LongWord; key: PChar; out_value: PChar; length: Pointer): Integer; cdecl; external;
function nvs_erase_key(h: LongWord; key: PChar): Integer; cdecl; external;
function nvs_commit(h: LongWord): Integer; cdecl; external;

var
  FlashReady: Boolean;
  Opened: Boolean;
  Handle: LongWord;
  Namespace: string;
  LastErr: Integer;

{ Initialise the partition once, then open the namespace once. 0 or an error. }
function Ready: Integer;
var rc: Integer;
begin
  if not FlashReady then
  begin
    rc := nvs_flash_init;
    if (rc = ESP_ERR_NVS_NO_FREE_PAGES) or (rc = ESP_ERR_NVS_NEW_VERSION_FOUND) then
    begin
      rc := nvs_flash_erase;
      if rc = 0 then rc := nvs_flash_init;
    end;
    if rc <> 0 then begin Ready := rc; Exit; end;
    FlashReady := True;
  end;
  if not Opened then
  begin
    if Namespace = '' then Namespace := 'pxx';
    rc := nvs_open(PChar(Namespace), NVS_READWRITE, @Handle);
    if rc <> 0 then begin Ready := rc; Exit; end;
    Opened := True;
  end;
  Ready := 0;
end;

function NvsOpenNamespace(const ns: string): Integer;
begin
  if Opened then nvs_close(Handle);
  Opened := False;
  Namespace := ns;
  LastErr := Ready;
  NvsOpenNamespace := LastErr;
end;

function NvsSetInt(const key: string; value: Int64): Integer;
begin
  LastErr := Ready;
  if LastErr = 0 then LastErr := nvs_set_i64(Handle, PChar(key), value);
  NvsSetInt := LastErr;
end;

function NvsGetInt(const key: string; fallback: Int64): Int64;
var v: Int64;
begin
  NvsGetInt := fallback;
  LastErr := Ready;
  if LastErr <> 0 then Exit;
  v := 0;
  LastErr := nvs_get_i64(Handle, PChar(key), @v);
  if LastErr = 0 then NvsGetInt := v;
end;

function NvsSetStr(const key, value: string): Integer;
begin
  LastErr := Ready;
  if LastErr = 0 then LastErr := nvs_set_str(Handle, PChar(key), PChar(value));
  NvsSetStr := LastErr;
end;

function NvsGetStr(const key, fallback: string): string;
var len: PtrUInt; s: string;
begin
  NvsGetStr := fallback;
  LastErr := Ready;
  if LastErr <> 0 then Exit;
  { ask for the length first; it counts the terminating NUL }
  len := 0;
  LastErr := nvs_get_str(Handle, PChar(key), nil, @len);
  if LastErr <> 0 then Exit;
  if len <= 1 then begin NvsGetStr := ''; Exit; end;
  SetLength(s, len);
  LastErr := nvs_get_str(Handle, PChar(key), PChar(s), @len);
  if LastErr <> 0 then Exit;
  SetLength(s, len - 1);
  NvsGetStr := s;
end;

function NvsErase(const key: string): Integer;
begin
  LastErr := Ready;
  if LastErr = 0 then LastErr := nvs_erase_key(Handle, PChar(key));
  NvsErase := LastErr;
end;

function NvsCommit: Integer;
begin
  LastErr := Ready;
  if LastErr = 0 then LastErr := nvs_commit(Handle);
  NvsCommit := LastErr;
end;

function NvsLastError: Integer;
begin
  NvsLastError := LastErr;
end;

{ ---- the Nil Python surface ---------------------------------------------- }

function set_int(key: string; value: Int64): Integer;
begin
  set_int := NvsSetInt(key, value);
end;

function get_int(key: string; fallback: Int64): Int64;
begin
  get_int := NvsGetInt(key, fallback);
end;

function set_str(key, value: string): Integer;
begin
  set_str := NvsSetStr(key, value);
end;

function get_str(key, fallback: string): string;
begin
  get_str := NvsGetStr(key, fallback);
end;

function erase(key: string): Integer;
begin
  erase := NvsErase(key);
end;

function commit: Integer;
begin
  commit := NvsCommit;
end;

function last_error: Integer;
begin
  last_error := NvsLastError;
end;

end.
