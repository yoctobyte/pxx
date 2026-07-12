{ SPDX-License-Identifier: Zlib }
unit unix;
{ Minimal FPC-compatible Unix shim (feature-synapse-compile-check).

  Synapse's synautil reads `Tzseconds` (local timezone offset, in seconds east
  of UTC) via `Result := TZSeconds div 60`. FPC's Unix unit fills this at unit
  init from the system zone file; we have no libc/tzset and reading the TZif
  database is out of scope here, so we expose it as 0 (UTC). That is correct for
  a UTC host and conservative elsewhere — HTTP date headers use GMT regardless,
  so the HTTP-client path is unaffected. Grow to a real /etc/localtime parse if a
  consumer needs true local offset.

  NOT a port of FPC's Unix unit. }

interface

var
  { Seconds east of UTC for the local zone. 0 = UTC (see unit note). }
  Tzseconds: LongInt;

{ Kernel hostname (FPC Unix.GetHostName). Read from procfs — no libc, no
  uname syscall wiring needed; empty string when procfs is absent. }
function GetHostName: string;

implementation

function GetHostName: string;
var
  f: TextFile;
  s: string;
begin
  Result := '';
  Assign(f, '/proc/sys/kernel/hostname');
  {$I-}
  Reset(f);
  {$I+}
  if IOResult <> 0 then Exit;
  ReadLn(f, s);
  Close(f);
  Result := s;
end;

initialization
  Tzseconds := 0;
end.
