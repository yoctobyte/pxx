{ THE MULTI-CANDIDATE SIBLING of test_method_arg_typecheck_fails.

  That file asserts the gate for a method with ONE candidate. This one asserts
  it where the class declares TWO overloads and the argument fits NEITHER --
  the case that fell out of the bottom of FindUMethOverloadAhead into
  FindUMethArity, the first name match whose arity fits, i.e. a guess.

  Measured 2026-09-07 before the fix: with `Take(LongInt)` and `Take(string)`,
  `Take(r)` for a record ran the LongInt body and printed 7, the record's first
  field read as an integer. A Double and a TObject reached the same body as 0.
  No refusal, no crash, a plausible wrong value -- and the ranking had ALREADY
  judged every candidate impossible, then thrown the judgement away.

  fpc 3.2.2 refuses all three lines. This file must NOT compile; the Makefile
  greps for the diagnostic.

  Both spellings are here on purpose. The bare call is the one people write
  inside a class body and was the permissive one; `Self.`-qualifying it went
  through the same probe and was equally permissive, so a fixture carrying only
  the bare spelling would not have distinguished "the bare path is loose" from
  "the probe is loose". It is the probe. }
{$mode objfpc}{$H+}
program movlfail;
type
  TRec = record a: LongInt; end;
  TT = class
    procedure Take(i: LongInt); overload;
    procedure Take(s: string); overload;
    procedure Go;
  end;

procedure TT.Take(i: LongInt); begin WriteLn('INT body: ', i); end;
procedure TT.Take(s: string); begin WriteLn('STR body: ', s); end;

procedure TT.Go;
var r: TRec; d: Double; o: TObject;
begin
  r.a := 7; d := 2.5; o := nil;
  Take(r);        { record   -> neither overload }
  Self.Take(d);   { Double   -> neither, and the qualified spelling too }
  Take(o);        { class    -> neither }
end;

var t: TT;
begin
  t := TT.Create;
  t.Go;
end.
