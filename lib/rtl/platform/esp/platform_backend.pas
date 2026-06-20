unit platform_backend;
{ ESP-IDF/FreeRTOS PAL backend selected by -Fulib/rtl/platform/esp. }

interface

function PalBackendPlatform: Integer;
function PalBackendHasFiles: Boolean;
function PalBackendHasSockets: Boolean;
function PalBackendHasThreads: Boolean;
function PalBackendHasDynlib: Boolean;

function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendClose(handle: Integer): Integer;

function PalBackendMonotonicMillis: Int64;
procedure PalBackendYield;

implementation

const
  PAL_PLATFORM_ESP_IDF = 2;
  PAL_ERR_UNSUPPORTED = -38;

{$ifdef CPU_XTENSA}{$define PXX_PAL_ESP_IDF_TARGET}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_PAL_ESP_IDF_TARGET}{$endif}

{$ifdef PXX_PAL_ESP_IDF_TARGET}
procedure vTaskDelay(ticks: Integer); external;
function esp_timer_get_time: Int64; external;
{$endif}

function PalBackendPlatform: Integer;
begin
  Result := PAL_PLATFORM_ESP_IDF;
end;

function PalBackendHasFiles: Boolean;
begin
  Result := False;
end;

function PalBackendHasSockets: Boolean;
begin
  Result := False;
end;

function PalBackendHasThreads: Boolean;
begin
  Result := False;
end;

function PalBackendHasDynlib: Boolean;
begin
  Result := False;
end;

function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendClose(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendMonotonicMillis: Int64;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := esp_timer_get_time div 1000;
{$else}
  Result := 0;
{$endif}
end;

procedure PalBackendYield;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  vTaskDelay(1);
{$endif}
end;

end.
