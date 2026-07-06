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

implementation

end.
