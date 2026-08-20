{ SPDX-License-Identifier: Zlib }
unit platform_types;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

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
