unit platform_types;

interface

type
  TPalFileStat = record
    Size: Int64;
    MTimeSec: Int64;
    Mode: Integer;
    IsDir: Boolean;
    IsFile: Boolean;
  end;

implementation

end.
