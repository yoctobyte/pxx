unit udeep3;
{ Bottom of a three-unit chain. One declaration of every KIND, because the
  non-transitive-uses rule is enforced by SIX separate name tables and a
  regression can re-open any one of them alone — which is exactly how it first
  shipped (routines and record types hidden, consts and enums leaking).
  bug-pascal-uses-non-transitivity-only-covers-routines-and-types }
interface
type
  TDeepRec = record a: Integer; end;
  TDeepEnum = (deA, deB, deC);
  TDeepArr = array[0..2] of Integer;
  TDeepAlias = Int64;
const
  DeepInt = 42;
  DeepStr = 'deep';
  DeepChar = 'z';
var
  DeepVar: Integer = 7;
function DeepFunc: Integer;
implementation
function DeepFunc: Integer; begin DeepFunc := 3; end;
end.
