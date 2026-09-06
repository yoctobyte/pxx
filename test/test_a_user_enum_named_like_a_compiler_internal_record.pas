{ A user ENUM whose name collides with one of the compiler's own internal
  descriptor records must be the user's enum.

  IsRecordType (symtab.inc) hard-codes fourteen names -- TToken, TSymbol,
  TProc, TParam, TFixup, TStrEntry, TRawToken, TTemplate, ... -- so that
  compiler.pas's own records carry known ids across the self-host. Those names
  are not reserved in FPC and real code uses them: fcl-passrc's pscanner.pp
  declares `TToken = (tkEOF, ...)`.

  The shadow guard consulted only the ALIAS table, and an enum is not an alias,
  so `array of TToken` recorded a tyRecord element while `t: TToken` stayed
  tyInteger -- the same type, two readings, in one declaration block.

  WHY THE ROWS ARE MIXED ON PURPOSE. The bug's own victim, pscanner's shell
  sort, has three assignments that fail and one that does not:

      Sorted[J] := Sorted[J+K]      { element to element -- BOTH sides wrong the
                                      same way, so the check agrees and passes }
      tk := Sorted[J]               { mixed -- reports }
      Sorted[J] := tk               { mixed -- reports }

  A same-shape move cannot see a systematic error in the shape. So every row
  below crosses the boundary: enum variable to element, element to enum
  variable, and enum used as an array INDEX -- never element to element.

  CASE IS PART OF THE CLAIM. IsRecordType compares case-SENSITIVELY, so
  `ttoken` and `TToken` reached different tables and one program held both
  readings. Both spellings appear below and must agree.

  bug-p-a-user-enum-loses-its-name-to-a-compiler-internal-record }
{$mode objfpc}
program test_a_user_enum_named_like_a_compiler_internal_record;
type
  TToken = (tkEOF, tkIdent, tkNumber);
  TProc  = (prRead, prWrite);
  TParam = (paIn, paOut, paVar);
var
  toks: array of TToken;         { the spelling that took the builtin record }
  lc:   array[ttoken] of String; { the spelling that took the enum }
  procs: array of TProc;
  pars: array of TParam;
  t: TToken;
  p: TProc;
  a: TParam;
  i: Integer;
begin
  SetLength(toks, 3);
  t := tkNumber;
  toks[0] := t;                  { enum var -> dyn element }
  toks[1] := tkIdent;
  t := toks[0];                  { dyn element -> enum var }
  WriteLn('token ', Ord(t), ' ', Ord(toks[1]), ' len=', Length(toks));

  for i := 0 to 2 do
    lc[TToken(i)] := 'n' + Chr(Ord('0') + i);
  WriteLn('index ', lc[tkEOF], ' ', lc[tkNumber], ' ', lc[t]);

  SetLength(procs, 2);
  p := prWrite;
  procs[0] := p;
  p := procs[0];
  WriteLn('proc ', Ord(p), ' ', Ord(procs[0]));

  SetLength(pars, 2);
  a := paVar;
  pars[1] := a;
  a := pars[1];
  WriteLn('param ', Ord(a), ' ', Ord(pars[1]), ' size=', SizeOf(a));
end.
