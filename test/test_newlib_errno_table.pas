{ NewlibToLinuxErrno became a byte table on 2026-10-12 (compiler/builtin/newliberrno.pas).
  OldErrno below is the case statement it replaced, kept verbatim as the
  oracle: every errno from -10 to 300 must map the same way. }
program test_newlib_errno_table;
uses newliberrno;
function OldErrno(newlibErrno: Integer): Integer;
begin
  case newlibErrno of
    35: OldErrno := 42;   { ENOMSG }
    36: OldErrno := 43;   { EIDRM }
    37: OldErrno := 44;   { ECHRNG }
    38: OldErrno := 45;   { EL2NSYNC }
    39: OldErrno := 46;   { EL3HLT }
    40: OldErrno := 47;   { EL3RST }
    41: OldErrno := 48;   { ELNRNG }
    42: OldErrno := 49;   { EUNATCH }
    43: OldErrno := 50;   { ENOCSI }
    44: OldErrno := 51;   { EL2HLT }
    45: OldErrno := 35;   { EDEADLK }
    46: OldErrno := 37;   { ENOLCK }
    50: OldErrno := 52;   { EBADE }
    51: OldErrno := 53;   { EBADR }
    52: OldErrno := 54;   { EXFULL }
    53: OldErrno := 55;   { ENOANO }
    54: OldErrno := 56;   { EBADRQC }
    55: OldErrno := 57;   { EBADSLT }
    56: OldErrno := 35;   { EDEADLOCK }
    57: OldErrno := 59;   { EBFONT }
    74: OldErrno := 72;   { EMULTIHOP }
    76: OldErrno := 73;   { EDOTDOT }
    77: OldErrno := 74;   { EBADMSG }
    80: OldErrno := 76;   { ENOTUNIQ }
    81: OldErrno := 77;   { EBADFD }
    82: OldErrno := 78;   { EREMCHG }
    83: OldErrno := 79;   { ELIBACC }
    84: OldErrno := 80;   { ELIBBAD }
    85: OldErrno := 81;   { ELIBSCN }
    86: OldErrno := 82;   { ELIBMAX }
    87: OldErrno := 83;   { ELIBEXEC }
    88: OldErrno := 38;   { ENOSYS }
    90: OldErrno := 39;   { ENOTEMPTY }
    91: OldErrno := 36;   { ENAMETOOLONG }
    92: OldErrno := 40;   { ELOOP }
    106: OldErrno := 97;   { EAFNOSUPPORT }
    107: OldErrno := 91;   { EPROTOTYPE }
    108: OldErrno := 88;   { ENOTSOCK }
    109: OldErrno := 92;   { ENOPROTOOPT }
    110: OldErrno := 108;   { ESHUTDOWN }
    112: OldErrno := 98;   { EADDRINUSE }
    113: OldErrno := 103;   { ECONNABORTED }
    114: OldErrno := 101;   { ENETUNREACH }
    115: OldErrno := 100;   { ENETDOWN }
    116: OldErrno := 110;   { ETIMEDOUT }
    117: OldErrno := 112;   { EHOSTDOWN }
    118: OldErrno := 113;   { EHOSTUNREACH }
    119: OldErrno := 115;   { EINPROGRESS }
    120: OldErrno := 114;   { EALREADY }
    121: OldErrno := 89;   { EDESTADDRREQ }
    122: OldErrno := 90;   { EMSGSIZE }
    123: OldErrno := 93;   { EPROTONOSUPPORT }
    124: OldErrno := 94;   { ESOCKTNOSUPPORT }
    125: OldErrno := 99;   { EADDRNOTAVAIL }
    126: OldErrno := 102;   { ENETRESET }
    127: OldErrno := 106;   { EISCONN }
    128: OldErrno := 107;   { ENOTCONN }
    129: OldErrno := 109;   { ETOOMANYREFS }
    131: OldErrno := 87;   { EUSERS }
    132: OldErrno := 122;   { EDQUOT }
    133: OldErrno := 116;   { ESTALE }
    134: OldErrno := 95;   { ENOTSUP }
    135: OldErrno := 123;   { ENOMEDIUM }
    138: OldErrno := 84;   { EILSEQ }
    139: OldErrno := 75;   { EOVERFLOW }
    140: OldErrno := 125;   { ECANCELED }
    141: OldErrno := 131;   { ENOTRECOVERABLE }
    142: OldErrno := 130;   { EOWNERDEAD }
    143: OldErrno := 86;   { ESTRPIPE }
    { PICOLIBC-only names (IDF 6 builds with picolibc; newlib stops at 143).
      The 124 names both define agree, measured against both toolchains'
      sys/errno.h (xtensa and riscv32 identical), so these five are the whole
      difference. }
    144: OldErrno := 133;   { EHWPOISON }
    145: OldErrno := 120;   { EISNAM }
    146: OldErrno := 127;   { EKEYEXPIRED }
    147: OldErrno := 129;   { EKEYREJECTED }
    148: OldErrno := 128;   { EKEYREVOKED }
  else
    OldErrno := newlibErrno;
  end;
end;


var i, bad: Integer;
begin
  bad := 0;
  for i := -10 to 300 do
    if NewlibToLinuxErrno(i) <> OldErrno(i) then begin Inc(bad); WriteLn('DIFF ', i, ' ', NewlibToLinuxErrno(i), ' ', OldErrno(i)); end;
  WriteLn('errtab bad=', bad);
end.
