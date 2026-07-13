{ A ROUTINE-LOCAL typed const that is an ARRAY OF CLASS REFERENCES.

      procedure TT.Go;
      const
        Map : array[TKind] of TBaseClass = (TA, TB);

  Every other element kind in the const-section parser forks on `isLocalConst` and routes
  a routine-local initializer to the LOCAL init list. The class-reference element branch
  did not: it always registered a PENDING GLOBAL initializer — holding the ROUTINE-LOCAL
  symbol index. That index is rolled back with the routine's scope (SymRollbackTo), so by
  the time main ran the pending initializers it pointed past the end of the symbol table.
  The result was a dangling IR_LEA in main, caught by the strict-IR verifier as
  "invalid symbol in lea" — an error pointing at the program's `begin`, with nothing
  whatsoever to say about the routine that actually caused it.

  Local inits already carry kind 5 (AN_CLASSREF, the scalar metaclass const) and the flush
  already honours an element index, so the array case needed no new machinery.

  This is the LAST wall in fcl-json's testjsondata.pp, which declares
    Const MyJSONInstanceTypes : Array[TJSONInstanceType] of TJSONDataClass = (TJSONData, ...);
  and now compiles end to end. Expected output is FPC's. }
program test_local_const_classref_array_b317;
{$mode objfpc}{$H+}

type
  TBase = class end;
  TBaseClass = class of TBase;
  TA = class(TBase) end;
  TB = class(TBase) end;
  TKind = (kA, kB);

{ NOTE: reading a metaclass ARRAY ELEMENT into a variable, or calling a virtual class
  method directly on one (`Map[k].Tag`), is a SEPARATE and still-open bug — the metaclass
  receiver check only accepts AN_IDENT, so an array element falls through and yields
  garbage. Filed as bug-pascal-metaclass-array-element-not-a-receiver. This test stays on
  the const itself and reads it through ClassName, which is the path that works. }

{ the local const, inside a routine — and read on BOTH calls, so a value that only
  survived the first call would show up }
procedure Show;
const
  Map : array[TKind] of TBaseClass = (TA, TB);
var
  k: TKind;
begin
  for k := Low(TKind) to High(TKind) do
    writeln(Ord(k), '=', Map[k].ClassName);
end;

{ the same thing at UNIT/PROGRAM scope must keep working (the global path) }
const
  GMap : array[TKind] of TBaseClass = (TB, TA);

var
  k: TKind;
begin
  Show;
  Show;
  for k := Low(TKind) to High(TKind) do
    writeln('g', Ord(k), '=', GMap[k].ClassName);
end.
