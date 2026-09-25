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

function NewlibToLinuxErrno(newlibErrno: Integer): Integer;
begin
  case newlibErrno of
    35: NewlibToLinuxErrno := 42;   { ENOMSG }
    36: NewlibToLinuxErrno := 43;   { EIDRM }
    37: NewlibToLinuxErrno := 44;   { ECHRNG }
    38: NewlibToLinuxErrno := 45;   { EL2NSYNC }
    39: NewlibToLinuxErrno := 46;   { EL3HLT }
    40: NewlibToLinuxErrno := 47;   { EL3RST }
    41: NewlibToLinuxErrno := 48;   { ELNRNG }
    42: NewlibToLinuxErrno := 49;   { EUNATCH }
    43: NewlibToLinuxErrno := 50;   { ENOCSI }
    44: NewlibToLinuxErrno := 51;   { EL2HLT }
    45: NewlibToLinuxErrno := 35;   { EDEADLK }
    46: NewlibToLinuxErrno := 37;   { ENOLCK }
    50: NewlibToLinuxErrno := 52;   { EBADE }
    51: NewlibToLinuxErrno := 53;   { EBADR }
    52: NewlibToLinuxErrno := 54;   { EXFULL }
    53: NewlibToLinuxErrno := 55;   { ENOANO }
    54: NewlibToLinuxErrno := 56;   { EBADRQC }
    55: NewlibToLinuxErrno := 57;   { EBADSLT }
    56: NewlibToLinuxErrno := 35;   { EDEADLOCK }
    57: NewlibToLinuxErrno := 59;   { EBFONT }
    74: NewlibToLinuxErrno := 72;   { EMULTIHOP }
    76: NewlibToLinuxErrno := 73;   { EDOTDOT }
    77: NewlibToLinuxErrno := 74;   { EBADMSG }
    80: NewlibToLinuxErrno := 76;   { ENOTUNIQ }
    81: NewlibToLinuxErrno := 77;   { EBADFD }
    82: NewlibToLinuxErrno := 78;   { EREMCHG }
    83: NewlibToLinuxErrno := 79;   { ELIBACC }
    84: NewlibToLinuxErrno := 80;   { ELIBBAD }
    85: NewlibToLinuxErrno := 81;   { ELIBSCN }
    86: NewlibToLinuxErrno := 82;   { ELIBMAX }
    87: NewlibToLinuxErrno := 83;   { ELIBEXEC }
    88: NewlibToLinuxErrno := 38;   { ENOSYS }
    90: NewlibToLinuxErrno := 39;   { ENOTEMPTY }
    91: NewlibToLinuxErrno := 36;   { ENAMETOOLONG }
    92: NewlibToLinuxErrno := 40;   { ELOOP }
    106: NewlibToLinuxErrno := 97;   { EAFNOSUPPORT }
    107: NewlibToLinuxErrno := 91;   { EPROTOTYPE }
    108: NewlibToLinuxErrno := 88;   { ENOTSOCK }
    109: NewlibToLinuxErrno := 92;   { ENOPROTOOPT }
    110: NewlibToLinuxErrno := 108;   { ESHUTDOWN }
    112: NewlibToLinuxErrno := 98;   { EADDRINUSE }
    113: NewlibToLinuxErrno := 103;   { ECONNABORTED }
    114: NewlibToLinuxErrno := 101;   { ENETUNREACH }
    115: NewlibToLinuxErrno := 100;   { ENETDOWN }
    116: NewlibToLinuxErrno := 110;   { ETIMEDOUT }
    117: NewlibToLinuxErrno := 112;   { EHOSTDOWN }
    118: NewlibToLinuxErrno := 113;   { EHOSTUNREACH }
    119: NewlibToLinuxErrno := 115;   { EINPROGRESS }
    120: NewlibToLinuxErrno := 114;   { EALREADY }
    121: NewlibToLinuxErrno := 89;   { EDESTADDRREQ }
    122: NewlibToLinuxErrno := 90;   { EMSGSIZE }
    123: NewlibToLinuxErrno := 93;   { EPROTONOSUPPORT }
    124: NewlibToLinuxErrno := 94;   { ESOCKTNOSUPPORT }
    125: NewlibToLinuxErrno := 99;   { EADDRNOTAVAIL }
    126: NewlibToLinuxErrno := 102;   { ENETRESET }
    127: NewlibToLinuxErrno := 106;   { EISCONN }
    128: NewlibToLinuxErrno := 107;   { ENOTCONN }
    129: NewlibToLinuxErrno := 109;   { ETOOMANYREFS }
    131: NewlibToLinuxErrno := 87;   { EUSERS }
    132: NewlibToLinuxErrno := 122;   { EDQUOT }
    133: NewlibToLinuxErrno := 116;   { ESTALE }
    134: NewlibToLinuxErrno := 95;   { ENOTSUP }
    135: NewlibToLinuxErrno := 123;   { ENOMEDIUM }
    138: NewlibToLinuxErrno := 84;   { EILSEQ }
    139: NewlibToLinuxErrno := 75;   { EOVERFLOW }
    140: NewlibToLinuxErrno := 125;   { ECANCELED }
    141: NewlibToLinuxErrno := 131;   { ENOTRECOVERABLE }
    142: NewlibToLinuxErrno := 130;   { EOWNERDEAD }
    143: NewlibToLinuxErrno := 86;   { ESTRPIPE }
  else
    NewlibToLinuxErrno := newlibErrno;
  end;
end;

end.
