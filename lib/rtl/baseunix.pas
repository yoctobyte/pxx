{ SPDX-License-Identifier: Zlib }
unit baseunix;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Minimal FPC-compatible BaseUnix shim (feature-synapse-compile-check).

  Only the surface the Synapse FPC/UNIX branch actually touches: the `timeval`
  type family and `fpgettimeofday`. Wall-clock comes from a CLOCK_REALTIME
  clock_gettime syscall (self-contained, like lib/rtl/ansiterm.pas — the raw
  syscall number is selected per arch here rather than going through the PAL
  public API, which has no clock surface yet).

  NOT a port of FPC's BaseUnix — grow it only as further units demand symbols. }

interface

type
  cint    = LongInt;
  ptimeval  = ^timeval;
  ptimezone = ^timezone;

  timeval = record
    tv_sec:  Int64;   { seconds since the Unix epoch }
    tv_usec: Int64;   { microseconds }
  end;
  TTimeVal = timeval;
  PTimeVal = ptimeval;

  timezone = record
    tz_minuteswest: cint;
    tz_dsttime:     cint;
  end;
  TTimeZone = timezone;
  PTimeZone = ptimezone;

{ Fills tp with the current wall-clock time. tzp is accepted for signature
  compatibility and ignored (CLOCK_REALTIME carries no zone). Returns 0 on
  success, -1 on failure. }
function fpgettimeofday(tp: ptimeval; tzp: ptimezone): cint;
function fpsettimeofday(tp: ptimeval; tzp: ptimezone): cint;


const
  { Linux errno values under FPC BaseUnix's ESys* names — the set Synapse's
    ssfpc.inc/synsock reference (feature-synapse-compile-check). x86-64/
    generic-Linux numbering. }
  ESysEINTR           = 4;
  ESysEBADF           = 9;
  ESysEACCES          = 13;
  ESysEFAULT          = 14;
  ESysEINVAL          = 22;
  ESysEMFILE          = 24;
  ESysEPIPE           = 32;
  ESysEWOULDBLOCK     = 11;    { = EAGAIN on Linux }
  ESysEINPROGRESS     = 115;
  ESysEALREADY        = 114;
  ESysENOTSOCK        = 88;
  ESysEDESTADDRREQ    = 89;
  ESysEMSGSIZE        = 90;
  ESysEPROTOTYPE      = 91;
  ESysENOPROTOOPT     = 92;
  ESysEPROTONOSUPPORT = 93;
  ESysESOCKTNOSUPPORT = 94;
  ESysEOPNOTSUPP      = 95;
  ESysEPFNOSUPPORT    = 96;
  ESysEAFNOSUPPORT    = 97;
  ESysEADDRINUSE      = 98;
  ESysEADDRNOTAVAIL   = 99;
  ESysENETDOWN        = 100;
  ESysENETUNREACH     = 101;
  ESysENETRESET       = 102;
  ESysECONNABORTED    = 103;
  ESysECONNRESET      = 104;
  ESysENOBUFS         = 105;
  ESysEISCONN         = 106;
  ESysENOTCONN        = 107;
  ESysESHUTDOWN       = 108;
  ESysETOOMANYREFS    = 109;
  ESysETIMEDOUT       = 110;
  ESysECONNREFUSED    = 111;
  ESysELOOP           = 40;
  ESysENAMETOOLONG    = 36;
  ESysEHOSTDOWN       = 112;
  ESysEHOSTUNREACH    = 113;
  ESysENOTEMPTY       = 39;
  ESysEUSERS          = 87;
  ESysEDQUOT          = 122;
  ESysESTALE          = 116;
  ESysEREMOTE         = 66;

implementation

uses platform;   { PalClockGetTime / PalClockSetTime -- see the note below }

{ THE SEVENTH PRIVATE CLOCK TABLE, and it is gone. baseunix carried its own
  `SysClockGettime` for four targets and, for the SETTER, a bare
  `{$ifdef CPUX86_64} 227 {$else} -1` -- so `fpsettimeofday` reported failure on
  every other target with a comment saying "until a consumer needs it". Both are
  the same substitution: an ARCH standing in for a capability that belongs to the
  platform, and a number table private to the unit that uses it.

  platform.pas has both directions for all six targets, and had them before this
  edit. `PalClockSetTime` existed with no getter beside it for a while, which is
  part of why each caller grew its own reader
  (bug-b-palnanosleep-answers-enosys-on-riscv32-because-rv32-has-no-nanosleep-syscall
  records the family); PalClockGetTime landed 2026-09-04 and closes that.

  For wasm32 this was one of the 518 IR_SYSCALL refusals in the corpus census:
  `if n = -1 then Exit` is a RUNTIME test in front of an instruction that is
  still EMITTED, so the whole body was refused rather than answering -1. }
function fpsettimeofday(tp: ptimeval; tzp: ptimezone): cint;
begin
  Result := -1;
  if tp = nil then Exit;
  { clock_settime(CLOCK_REALTIME); build the timespec from the caller's timeval.
    Still fails with -1 (EPERM) for unprivileged callers, which is exactly what
    Synapse's SetUTTime expects on an ordinary box -- the difference is that it
    now fails for the RIGHT reason on the five non-x86-64 targets instead of
    because the number was missing. }
  if PalClockSetTime(0, tp^.tv_sec, Int64(tp^.tv_usec) * 1000) = 0 then
    Result := 0;
end;

function fpgettimeofday(tp: ptimeval; tzp: ptimezone): cint;
var sec, nsec: Int64;
begin
  Result := -1;
  if tp = nil then Exit;
  if PalClockGetTime(0, sec, nsec) <> 0 then Exit;   { 0 = CLOCK_REALTIME }
  tp^.tv_sec  := sec;
  tp^.tv_usec := nsec div 1000;
  Result := 0;
end;

end.
