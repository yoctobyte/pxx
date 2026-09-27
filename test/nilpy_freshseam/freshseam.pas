{ SPDX-License-Identifier: Zlib }
unit freshseam;
{$MODE PXX}
{ For test/test_nilpy_a_pascal_result_is_released_once_whatever_its_shape.npy:
  every return shape ClassifyProcResultFresh gives a verdict on (the same
  bodies as test/test_result_fresh_verdicts.pas), called from NilPy. TA counts
  its own constructions and destructions so the test can tell a leak (alive
  grows) from a double free (gone passes made). }
interface
type
  TA = class
  public
    v: Integer;
    other: TA;
    items: array[0..3] of TA;
    constructor Create(av: Integer);
    destructor Destroy; override;
    function Fresh: TA;
    function Me: TA;
    function Via: TA;
    function Named: TA;
    function NamedSelf: TA;
    function Mixed: TA;
    function ViaLocal: TA;
    function OrNil: TA;
    function Fld: TA;
    function Element(i: Integer): TA;
    procedure Fill;
  end;
function MakeA: TA;
function Cached: TA;
function MkLocal: TA;
function PassThrough(a: TA): TA;
function made: Integer;
function gone: Integer;
implementation
var NMade, NGone: Integer;
constructor TA.Create(av: Integer); begin v := av; NMade := NMade + 1; end;
destructor TA.Destroy; begin NGone := NGone + 1; inherited Destroy; end;
function MakeA: TA;
begin
  Result := TA.Create(0);
end;
function MkLocal: TA;
var t: TA;
begin
  t := TA.Create(0);
  MkLocal := t;
end;
function PassThrough(a: TA): TA;
begin
  Result := a;
end;
function TA.Fresh: TA;
begin
  Result := TA.Create(0);
end;
function TA.Me: TA;
begin
  Result := Self;
end;
function TA.Via: TA;
begin
  Result := MakeA;
end;
function TA.Named: TA;
begin
  Named := TA.Create(0);
end;
function TA.NamedSelf: TA;
begin
  NamedSelf := Self;
end;
{ v > 0: the borrowed arm (Self); v = 0: the fresh arm }
function TA.Mixed: TA;
begin
  if v > 0 then Exit(Self);
  Result := TA.Create(0);
end;
function TA.ViaLocal: TA;
var t: TA;
begin
  t := TA.Create(0);
  Result := t;
end;
{ v > 0: nil; v = 0: fresh }
function TA.OrNil: TA;
begin
  if v > 0 then Exit(nil);
  Result := TA.Create(0);
end;
function TA.Fld: TA;
begin
  Result := other;
end;
function TA.Element(i: Integer): TA;
begin
  Result := items[i];
end;
procedure TA.Fill;
begin
  other := TA.Create(5);
  items[2] := TA.Create(7);
end;
var GCache: TA;
function Cached: TA;
begin
  if GCache = nil then GCache := TA.Create(9);
  Result := GCache;
end;
function made: Integer; begin made := NMade; end;
function gone: Integer; begin gone := NGone; end;
end.
