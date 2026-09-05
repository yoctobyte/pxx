{ The positive half of test_method_array_arg_scalar_param_fails.pas: the
  array-shaped arguments a METHOD call must keep ACCEPTING once the overload
  probe can see the argument-match side channels.

  Every row here is a channel arm that says "tolerate", and each one is a way
  the refusal could be wrong rather than merely absent:

    CharArr    an `array[..] of Char` IS a string in Pascal, so MatchArgArray
               must not refuse it against a string parameter -- that is what
               MatchArgArrayElemTk exists for
               (bug-p-a-char-array-argument-stopped-binding-a-string-parameter)
    OpenArr    an open-array parameter takes an array argument by definition

  A dyn-array-to-Pointer row was tried here and REMOVED: pxx's array-vs-scalar
  guard exempts tyPointer on purpose, but fpc 3.2.2 refuses `d.PtrParam(dyn,3)`
  with `Incompatible type for arg no. 1: Got "TDyn", expected "Pointer"`, so
  asserting acceptance would have pinned a divergence into a row whose whole
  point is that the oracle agrees.
    Scalar     the ordinary case, unchanged

  It also pins the INDEXING. The channels are filled at the PARAMETER slot,
  and Params[0] is Self on every method, so an off-by-one would compare each
  argument against its neighbour's parameter -- which these rows, having
  different parameter shapes at positions 1 and 2, are built to catch. }
{$mode objfpc}
program marrok;
type
  TCA = array[0..3] of Char;
  TIA = array[0..2] of Integer;
  TD = class
    procedure CharArr(const s: AnsiString; n: Integer);
    procedure OpenArr(n: Integer; const a: array of Integer);
    procedure Scalar(v: Integer);
  end;
procedure TD.CharArr(const s: AnsiString; n: Integer);
  begin WriteLn('chararr [', s, '] ', n); end;
procedure TD.OpenArr(n: Integer; const a: array of Integer);
  begin WriteLn('openarr ', n, ' ', Length(a), ' ', a[0]); end;
procedure TD.Scalar(v: Integer);
  begin WriteLn('scalar ', v); end;
var d: TD; ca: TCA; ia: TIA;
begin
  d := TD.Create;
  ca[0] := 'a'; ca[1] := 'b'; ca[2] := 'c'; ca[3] := #0;
  ia[0] := 11; ia[1] := 22; ia[2] := 33;
  d.CharArr(ca, 1);
  d.OpenArr(2, ia);
  d.Scalar(44);
end.
