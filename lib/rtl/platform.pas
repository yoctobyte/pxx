unit platform;
{ Minimal Platform Abstraction Layer (PAL).

  This is the only RTL unit that may branch on PXX_PLATFORM_* while the Pascal
  unit-search-path backend selector is still missing. Higher-level IO,
  networking, time, and CRTL units should depend on this interface rather than
  branching on platform names themselves. }

interface

const
  PAL_STDIN  = 0;
  PAL_STDOUT = 1;
  PAL_STDERR = 2;

  PAL_PLATFORM_POSIX = 1;
  PAL_PLATFORM_ESP_IDF = 2;

  PAL_OPEN_READ   = 0;
  PAL_OPEN_WRITE  = 1;
  PAL_OPEN_RDWR   = 2;
  PAL_OPEN_CREATE = $40;
  PAL_OPEN_TRUNC  = $200;
  PAL_OPEN_APPEND = $400;

  PAL_ERR_UNSUPPORTED = -38; { Linux ENOSYS, used as the portable "not here" }

function PalPlatform: Integer;
function PalHasFiles: Boolean;
function PalHasSockets: Boolean;
function PalHasThreads: Boolean;
function PalHasDynlib: Boolean;

function PalUnsupported: Integer;

function PalOpen(path: PChar; flags, mode: Integer): Integer;
function PalRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalClose(handle: Integer): Integer;

function PalMonotonicMillis: Int64;
procedure PalYield;

implementation

function PalPlatform: Integer;
begin
{$ifdef PXX_PLATFORM_ESP}
  Result := PAL_PLATFORM_ESP_IDF;
{$else}
  Result := PAL_PLATFORM_POSIX;
{$endif}
end;

function PalHasFiles: Boolean;
begin
{$ifdef PXX_HAS_FILES}
  Result := True;
{$else}
  Result := False;
{$endif}
end;

function PalHasSockets: Boolean;
begin
{$ifdef PXX_HAS_SOCKETS}
  Result := True;
{$else}
  Result := False;
{$endif}
end;

function PalHasThreads: Boolean;
begin
{$ifdef PXX_HAS_THREADS}
  Result := True;
{$else}
  Result := False;
{$endif}
end;

function PalHasDynlib: Boolean;
begin
{$ifdef PXX_HAS_DYNLIB}
  Result := True;
{$else}
  Result := False;
{$endif}
end;

function PalUnsupported: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{$ifdef PXX_PLATFORM_ESP}

{ ESP PAL is IDF/FreeRTOS-shaped. Byte handles stay unsupported until the
  project has VFS/lwIP bindings. IDF symbols are referenced only for ESP CPU
  targets so native `--platform=esp` smoke tests can still run. }
{$ifdef CPU_XTENSA}{$define PXX_PAL_ESP_IDF_TARGET}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_PAL_ESP_IDF_TARGET}{$endif}

{$ifdef PXX_PAL_ESP_IDF_TARGET}
procedure vTaskDelay(ticks: Integer); external;
function esp_timer_get_time: Int64; external;
{$endif}

function PalOpen(path: PChar; flags, mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalRead(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalClose(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalMonotonicMillis: Int64;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := esp_timer_get_time div 1000;
{$else}
  Result := 0;
{$endif}
end;

procedure PalYield;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  vTaskDelay(1);
{$endif}
end;

{$else}

const
{$ifdef CPUX86_64}
  SYS_read = 0; SYS_write = 1; SYS_close = 3; SYS_openat = 257;
{$endif}
{$ifdef CPU_I386}
  SYS_read = 3; SYS_write = 4; SYS_close = 6; SYS_openat = 295;
{$endif}
{$ifdef CPU_AARCH64}
  SYS_read = 63; SYS_write = 64; SYS_close = 57; SYS_openat = 56;
{$endif}
{$ifdef CPU_ARM32}
  SYS_read = 3; SYS_write = 4; SYS_close = 6; SYS_openat = 322;
{$endif}
  PAL_AT_FDCWD = -100;

function PalOpen(path: PChar; flags, mode: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_openat, PAL_AT_FDCWD, Int64(path), flags, mode, 0, 0));
end;

function PalRead(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_read, handle, Int64(buf), len, 0, 0, 0);
end;

function PalWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_write, handle, Int64(buf), len, 0, 0, 0);
end;

function PalClose(handle: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_close, handle, 0, 0, 0, 0, 0));
end;

function PalMonotonicMillis: Int64;
begin
  { Clock backends will grow here. Keep the interface stable now. }
  Result := 0;
end;

procedure PalYield;
begin
end;

{$endif}

end.
