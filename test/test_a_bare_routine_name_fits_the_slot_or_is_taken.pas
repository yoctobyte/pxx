{ THE DELPHI @-OPTIONAL RULE IS A DISAMBIGUATION, AND ITS TEST WAS "IS THE
  RESULT PROCEDURAL AT ALL" RATHER THAN "DOES THE RESULT FIT THIS SLOT".

  `p := F` with no `@` means F's ADDRESS -- unless F is a parameterless function
  whose result fits p, in which case Delphi CALLS it. ProcResultSatisfiesKind
  makes that call, and for a plain procedural target it asked only
  `RetType = tyPointer and ProcRetProcSig >= 0`. Every procedural return passes
  that, including one of a DIFFERENT shape than the slot, so `fo := MkOuter` for
  `TOuter = function: TInner` called MkOuter and stored the returned TInner into
  a TOuter slot with no diagnostic. The next `fo()` segfaulted.

  Its own comment said the test was "deliberately NARROW ... only when the
  routine's result actually FITS the target". The narrow test was never written;
  the comment described the intention.

  BOTH DIRECTIONS ARE ASSERTED, because a fix that only tightens is indis-
  tinguishable here from one that disables the clause:
    - rows A and B are the ADDRESS reading (the counter must stay 0),
    - row C is the CALL reading and it must SURVIVE -- a matching result still
      gets called, which is the whole reason the clause exists,
    - row D uses the taken address, which is what actually crashed.

  Row A is the paramless-ORDINAL control: it was already correct, and it is what
  says the defect is the fit test rather than the rule.

  .expected is fpc 3.2.2 -Mdelphi's own output.
  bug-p-a-bare-routine-name-whose-result-is-itself-procedural-is-called-not-taken }
{$mode delphi}
program test_a_bare_routine_name_fits_the_slot_or_is_taken;
type
  TInner = function(x: LongInt): LongInt;
  TOuter = function: TInner;      { result shape DIFFERS from a TInner slot }
  TNul   = function: LongInt;
  TPl    = procedure;
var
  hitSrc, hitMk, hitPlain, hitMakePl: LongInt;
function Inner(x: LongInt): LongInt; begin Result := x + 1; end;
function Src: LongInt;    begin Inc(hitSrc); Result := 7; end;
function MkOuter: TInner; begin Inc(hitMk);  Result := @Inner; end;
procedure Plain;          begin Inc(hitPlain); end;
function MakePl: TPl;     begin Inc(hitMakePl); Result := @Plain; end;
var
  f: TNul; fo: TOuter; p: TPl;
begin
  hitSrc := 0; hitMk := 0; hitPlain := 0; hitMakePl := 0;

  { A -- paramless ORDINAL result does not fit a procedural slot: ADDRESS }
  f := Src;
  WriteLn('A ', hitSrc);

  { B -- paramless PROCEDURAL result of the WRONG shape: still the ADDRESS }
  fo := MkOuter;
  WriteLn('B ', hitMk);

  { C -- paramless procedural result of the MATCHING shape: Delphi CALLS it }
  p := MakePl;
  WriteLn('C ', hitMakePl);

  { D -- and the addresses taken in A and B are the right ones }
  WriteLn('D ', f(), ' ', fo()(41));

  { E -- the value row C stored is Plain, reached through the slot }
  p;
  WriteLn('E ', hitPlain, ' ', hitMakePl);
end.
