program test_declared_sees_a_used_units_declarations;
{$mode delphi}
{ `$if declared(X)` ACROSS A `uses`, AND THE STATE THE ANSWER COSTS.

  PasCondNameDeclared answers by scanning the token stream, and a used unit's
  tokens are put there by LexAppend at PARSE time -- so every conditional in
  this file was decided before a single unit token existed, and `declared`
  answered False for a type the same program then constructs. The failure was
  silent in the worst way: False is indistinguishable from a correct negative,
  and a correct negative is the common case.

  FOUR ROWS, AND THE SECOND IS A CONTROL FOR THE FIRST.

  `type` is the fix: a name declared only in decl_probe_unit, found. `fn` is the
  same question for a ROUTINE, which the scan reaches through a different arm
  (expectRoutine, not expectName in a declaration section).

  `leak` is the row that fails if the answer is bought carelessly. Answering
  `type` means LEXING the used unit, and lexing runs its directives -- so
  decl_probe_unit's `$DEFINE DECL_PROBE_LEAKED` escapes into THIS file's
  `$ifdef` unless the probe saves and restores the lexer state around itself.
  Measured 2026-09-09 with the probe wired and the save/restore absent: this row
  printed 1 where fpc prints 0. It is not a hypothetical -- it is
  bug-p-a-units-define-leaks-into-the-units-it-uses being reintroduced by a
  second copy of a state list, and tools/probe_state_lists.py checks the two
  lists against each other for the same reason.

  `absent` is the row that keeps the fix honest in the other direction: a name
  that is nowhere must still answer False, or `declared` has stopped being an
  answer and become a yes. It matters because REFUSING was the tempting repair
  and would have been wrong -- False is what this operator exists to return.

  Byte-identical to fpc 3.2.2. Every value is 0 or 1 by the nature of the
  operator, so the rows are read together: 1/1/0/0 is the only combination that
  is not also produced by some simpler mistake -- always-True gives 1/1/1/1,
  always-False gives 0/0/0/0, and a probe with no state discipline gives 1/1/1/0.
  bug-p-declared-cannot-see-a-used-units-declarations }
uses decl_probe_unit, decl_probe_gen;
const
  {$if declared(TProbeSeenType)} A = 1; {$else} A = 0; {$endif}
  {$if declared(ProbeUnitFn)}    B = 1; {$else} B = 0; {$endif}
  {$ifdef DECL_PROBE_LEAKED}     C = 1; {$else} C = 0; {$endif}
  {$if declared(NoSuchNameAnywhereAtAll)} D = 1; {$else} D = 0; {$endif}
  { THE ARITY SPELLING. `<>` is one parameter, `<,>` two, `<,,>` three, and a
    BARE name asks for arity 0 -- a real question, not a wildcard, which is why
    E is 0 where only TGenDelphi<T> and TGenDelphi<T,S,R> exist. }
  {$if declared(TGenDelphi)}    E = 1; {$else} E = 0; {$endif}
  {$if declared(TGenDelphi<>)}  F = 1; {$else} F = 0; {$endif}
  {$if declared(TGenDelphi<,>)} G = 1; {$else} G = 0; {$endif}
  {$if declared(TGenDelphi<,,>)} H = 1; {$else} H = 0; {$endif}
  { …and the objfpc spelling, where `generic` is a plain identifier that ate the
    scan's declaration slot. J is the row that separates a working scan from one
    that never examined the name: I is False under both. }
  {$if declared(TGenFpc)}       I = 1; {$else} I = 0; {$endif}
  {$if declared(TGenFpc<,>)}    J = 1; {$else} J = 0; {$endif}
var t: TProbeSeenType;
begin
  WriteLn('type   ', A);
  WriteLn('fn     ', B);
  WriteLn('leak   ', C);
  WriteLn('absent ', D);
  WriteLn('gen    ', E, F, G, H);
  WriteLn('objfpc ', I, J);
  t := TProbeSeenType.Create;
  t.v := ProbeUnitFn;
  WriteLn('use    ', t.v);
end.
