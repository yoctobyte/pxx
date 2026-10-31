{ SPDX-License-Identifier: Zlib }
unit newliberrno;

{$MODE PXX}
{ NEWLIB'S ERRNO, IN LINUX NUMBERING -- the one copy of this table. The PAL
  contract everywhere is -errno in Linux's numbering, and newlib's differs for
  69 names: ETIMEDOUT is 116 there, 110 on Linux. GENERATED, not recalled: the
  ESP toolchain's sys/errno.h (xtensa and riscv32 identical) joined by NAME with
  CPython's errno module, listing only the names whose numbers differ; the
  other 50 pass through.

  A unit of its own, with no uses, because it has two consumers that share
  nothing else: NilPy's pypal (file I/O on ESP-IDF) and Pascal's
  lib/rtl/platform/esp/platform_backend.pas (sockets). pypal cannot be the
  host -- it needs the builtin string helpers, which a Pascal ESP program does
  not link -- and that is why platform_backend carried its own copy until now. }

interface

function NewlibToLinuxErrno(newlibErrno: Integer): Integer;

implementation

const
  { Linux's number for newlib/picolibc errno 35..148, one byte each. A TABLE,
    not the case statement it was: the ladder compiled to ~3.9 KB of riscv32
    code on a C3 for what is 114 bytes of data (remote_thermostat, 2026-10-12).
    Entries where the two numberings agree hold their own index. The case
    arms it replaces, with their names, are in git history; this table was
    generated from them, not retyped. }
  NewlibErrnoLo = 35;
  NewlibErrnoHi = 148;
  NewlibToLinuxTab: array[NewlibErrnoLo..NewlibErrnoHi] of Byte = (
     42,  43,  44,  45,  46,  47,  48,  49,  50,  51,  35,  37,   { 35..46 }
     47,  48,  49,  52,  53,  54,  55,  56,  57,  35,  59,  58,   { 47..58 }
     59,  60,  61,  62,  63,  64,  65,  66,  67,  68,  69,  70,   { 59..70 }
     71,  72,  73,  72,  75,  73,  74,  78,  79,  76,  77,  78,   { 71..82 }
     79,  80,  81,  82,  83,  38,  89,  39,  36,  40,  93,  94,   { 83..94 }
     95,  96,  97,  98,  99, 100, 101, 102, 103, 104, 105,  97,   { 95..106 }
     91,  88,  92, 108, 111,  98, 103, 101, 100, 110, 112, 113,   { 107..118 }
    115, 114,  89,  90,  93,  94,  99, 102, 106, 107, 109, 130,   { 119..130 }
     87, 122, 116,  95, 123, 136, 137,  84,  75, 125, 131, 130,   { 131..142 }
     86, 133, 120, 127, 129, 128   { 143..148 }
  );

function NewlibToLinuxErrno(newlibErrno: Integer): Integer;
begin
  if (newlibErrno >= NewlibErrnoLo) and (newlibErrno <= NewlibErrnoHi) then
    NewlibToLinuxErrno := NewlibToLinuxTab[newlibErrno]
  else
    NewlibToLinuxErrno := newlibErrno;
end;

end.
