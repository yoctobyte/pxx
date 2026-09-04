{ SPDX-License-Identifier: Zlib }
unit platform_types;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

{ Per-call send/recv flags. PAL'S OWN NUMBERS, NOT THE HOST OS'S, and the
  reason is measured rather than stylistic: Linux and lwIP use the SAME small
  bits for DIFFERENT flags. Linux MSG_PEEK is 2; lwIP MSG_PEEK is 1 and 2 is
  its MSG_WAITALL, which its own header marks "Unimplemented". Passing a Linux
  flag word through to lwIP would therefore turn a peek into a no-op that
  CONSUMES the data -- the exact failure this parameter exists to fix, moved to
  another target and given a different cause.
  (/home/neo/esp/esp-idf/components/lwip/lwip/src/include/lwip/sockets.h:269-274,
  read rather than remembered.)

  THE VALUES ARE DELIBERATELY IN A RANGE NEITHER OS USES. If they matched
  Linux's, the posix backend would work by accident with the translation
  missing, and the mistake would be invisible on the only target that runs the
  test. Here a backend that passes `flags' through untranslated sets bits both
  kernels ignore, so the effective flag word is 0 and the peek-twice assertion
  fails loudly on the first run.

  MSG_NOSIGNAL IS NOT IN THIS LIST ON PURPOSE. It is not a choice a caller
  makes -- the posix backend ORs it into every send unconditionally, because a
  dead peer must yield EPIPE rather than killing the process, and a caller
  passing flags=0 must not lose that. See PalIgnoreSignal's comment. }
const
  PAL_MSG_PEEK     = $00100000;  { read without consuming }
  PAL_MSG_OOB      = $00200000;  { out-of-band data }
  PAL_MSG_DONTWAIT = $00400000;  { this call only is non-blocking }
  PAL_MSG_WAITALL  = $00800000;  { block until len bytes are in }
  PAL_MSG_ALL      = PAL_MSG_PEEK or PAL_MSG_OOB or PAL_MSG_DONTWAIT or PAL_MSG_WAITALL;

  { EINVAL. Lives beside the flags it exists for: a backend handed a flag bit
    it does not recognise must REFUSE rather than mask it off, or a caller's
    typo becomes a flag word the kernel ignores -- which is exactly what a
    working flags parameter looks like from the outside. }
  PAL_ERR_INVALID = -22;

type
  TPalFileStat = record
    Size: Int64;
    MTimeSec: Int64;
    Mode: Integer;
    IsDir: Boolean;
    IsFile: Boolean;
    { extended fields for the C stat() surface (sqlite's POSIX lock manager keys
      file identity on (Dev,Ino), so these must be real, not zero) }
    Ino: Int64;
    Dev: Int64;
    Blocks: Int64;
    BlkSize: Integer;
    { st_nlink / st_uid / st_gid / st_rdev and the OTHER two timestamps. crtl's
      stat() hardcoded nlink to 1, uid/gid/rdev to 0, and reported MTime for
      atime and ctime as well — all silently, so a caller comparing atime, or
      spotting a hard link by nlink > 1, got a plausible wrong answer. statx
      returns every one of these already; they were simply never carried. }
    Nlink: Int64;
    Uid: Integer;
    Gid: Integer;
    Rdev: Int64;
    ATimeSec: Int64;
    CTimeSec: Int64;
  end;

  { An IPv6 address as its 16 wire-order bytes. Deliberately a byte array rather
    than four LongWords: an IPv6 address IS a byte string on the wire, and every
    LongWord view invites a byte-swap that should not happen. Lives here, beside
    TPalFileStat, so both the PAL facade and each backend can name it. }
  TPalIn6Addr = record
    Bytes: array[0..15] of Byte;
  end;

implementation

end.
