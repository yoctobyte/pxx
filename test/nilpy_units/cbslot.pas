unit cbslot;
{ Procedural slots of DIFFERENT shapes, so one NilPy def handed to two of them
  needs two thunks. The cache key is the PAIR (def, signature); keying on the
  def alone -- which all three sibling synthesizers do, correctly, because
  their shape is a function of the routine -- would hand the second slot the
  first slot's thunk and call it with the wrong convention.
  feature-n-a-nilpy-def-has-no-native-abi-entry-point-to-hand-to-a-c-callback }
interface
type
  TTwoInt  = function(a, b: Integer): Integer;
  TOneInt  = function(a: Integer): Integer;
  TTwoDbl  = function(a, b: Double): Double;
  TSlots = class
    two: TTwoInt;
    one: TOneInt;
    dbl: TTwoDbl;
  end;
function MkTwo(f: TTwoInt): TSlots;
function MkOne(f: TOneInt): TSlots;
function MkDbl(f: TTwoDbl): TSlots;
function FillTwoAndOne(f2: TTwoInt; f1: TOneInt): TSlots;
function CallTwo(s: TSlots): Integer;
function CallOne(s: TSlots): Integer;
function MkEmpty: TSlots;
function TheMaker(a, b: Integer): Integer;
function CallDbl(s: TSlots): Double;
implementation
function MkTwo(f: TTwoInt): TSlots;
begin Result := TSlots.Create; Result.two := f; end;
function MkOne(f: TOneInt): TSlots;
begin Result := TSlots.Create; Result.one := f; end;
function MkDbl(f: TTwoDbl): TSlots;
begin Result := TSlots.Create; Result.dbl := f; end;
{ BOTH slots in ONE call, so the two thunks are minted at the same site }
function FillTwoAndOne(f2: TTwoInt; f1: TOneInt): TSlots;
begin Result := TSlots.Create; Result.two := f2; Result.one := f1; end;
{ An instance with every slot EMPTY, so a store from NilPy is the only thing
  that can make it callable -- a slot pre-filled from Pascal would pass whether
  or not the store worked. }
function MkEmpty: TSlots;
begin Result := TSlots.Create; Result.two := nil; Result.one := nil; Result.dbl := nil; end;
function TheMaker(a, b: Integer): Integer;
begin Result := a * 100 + b; end;
function CallTwo(s: TSlots): Integer;
begin Result := s.two(5, 2); end;
function CallOne(s: TSlots): Integer;
begin Result := s.one(7); end;
function CallDbl(s: TSlots): Double;
begin Result := s.dbl(1.5, 2.25); end;
end.
