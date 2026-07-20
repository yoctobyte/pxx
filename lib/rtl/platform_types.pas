{ SPDX-License-Identifier: Zlib }
unit platform_types;

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
