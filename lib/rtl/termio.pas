{ SPDX-License-Identifier: Zlib }
unit termio;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Minimal FPC-compatible termio shim (feature-synapse-compile-check). Synapse's
  ssfpc.inc references only the three ioctl request constants below (for socket
  byte-count / non-blocking / async toggles). The full termios/serial surface is
  not provided — grow only as a consumer needs it. Linux ioctl values, shared
  across our LE targets.

  GROWN 2026-09-11 for the second consumer: FPC's own compiler calls
  `termio.IsATTY(t)` from comptty.pas:66, which is where the FPC-compiler-source
  march stopped. Both of fpc's overloads are here, with fpc's return type —
  `cint`, not Boolean: its caller writes `termio.IsATTY(t)=1`, so answering
  Boolean would not compile at the call site that motivated this. }

interface

uses pxxcio;

const
  FIONREAD = $541B;   { bytes available to read }
  FIONBIO  = $5421;   { set/clear non-blocking }
  FIOASYNC = $5452;   { set/clear async (SIGIO) }

{ 1 when the handle is a terminal, 0 otherwise — fpc's
  rtl/unix/termiosh.inc:31-32, both overloads, both returning cint. }
function IsATTY(Handle: Integer): Integer;
function IsATTY(var f: Text): Integer;

implementation

function IsATTY(Handle: Integer): Integer;
begin
  { __pxx_isatty IS the TCGETS ioctl, which is what libc does and the only test
    that separates a terminal from another character device. Reused rather than
    reimplemented here: a second copy of that knowledge is how the two answers
    drift apart, and pxxcio's comment carries the reasoning. }
  IsATTY := __pxx_isatty(Handle);
end;

function IsATTY(var f: Text): Integer;
begin
  IsATTY := __pxx_isatty(f.Handle);
end;

end.
