{ Helper unit for b292: its initialization section reads a class const. }
unit constinit;

interface

type
  TD = class
  public
    const
      SepsArr: array[Boolean] of string = (', ', ',');
    class var Captured: string;
    class procedure Determine; static;
  end;

const
  Seps: array[Boolean] of string = (', ', ',');

implementation

class procedure TD.Determine;
begin
  Captured := SepsArr[False];
end;

initialization
  { runs BEFORE the program body -- and must see the constants already initialised }
  TD.Determine;
end.
