program test_delphi_generic_arg_declared_later;
{ mode Delphi: a generic's ARGUMENT may be declared after the template. A Pascal
  type section imposes no declaration order and FPC resolves the whole section,
  so "declare the container before the thing it contains" is not a rule Delphi
  code follows. Every value here is FPC 3.2.2's on this same source.

  DelphiRewriteGenericUses spliced its minted alias declarations immediately
  behind the TEMPLATE, so everything an alias named had to be declared by that
  point. `TE = TBox<TOuter>;` with TOuter below TBox failed with
  `unknown type: TOuter` -- reported at a line inside TBox's own body, which the
  author did not write, so the diagnostic and the fix were nowhere near each
  other. objfpc was never affected: there the alias is emitted at the use.

  The alias is pinned between two constraints and only one position satisfies
  both. Hand-written in all three, on the identical program:

    A  behind the TEMPLATE (what it did)   `unknown type: TOuter`
    B  before the declaration that USES it  compiles
    C  at the END of the type section       `unknown type: TBox_TOuter`

  B is the only anchor that can satisfy both an in-section use, because the use
  site is legal Pascal (everything it names is declared) and nothing referring to
  the alias precedes its own declaration. C is right for a use OUTSIDE the
  section -- a var section, a routine body -- where every user is later by
  construction. One forward walk answers both: stop at the use or at the end of
  the section, whichever comes first.

  Arms 6 and 7 are the two the ticket listed as unanswered, and they are the
  reason the walk stops at the section rather than giving up there.
  bug-p-a-delphi-mode-generic-argument-must-be-declared-before-the-template }
{$mode delphi}

type
  TBox<T> = class
    V: T;
  end;

  { 1. the plain case: argument declared BELOW the template }
  TLater = class
    K: Integer;
  end;
  TE1 = TBox<TLater>;

  { 2. the use sits in a CLASS FIELD, so the nearest preceding `;` is inside a
       class body and splicing there would be nonsense -- the anchor has to be
       the start of the enclosing top-level declaration, not the previous `;` }
  TFwdArg = class;
  THolder = class
    F: TBox<TFwdArg>;
  end;
  TFwdArg = class
    K: Integer;
  end;

  { 3. two tuples first used in DIFFERENT declarations: one splice each, and
       each shifts every later index }
  TA = class K: Integer; end;
  TE2 = TBox<TA>;
  TB = class M: Integer; end;
  TE3 = TBox<TB>;

  { 4. a procedural TYPE and a bodiless class in the section the walk crosses.
       `X = procedure(...)` stays in the section; a bare heading ends it, and a
       bodiless `class;` opens no body to count. }
  TProcT = procedure(x: Integer);
  TBodiless = class;
  TBodiless = class(TA) end;

  { 5. nested: the outer alias names the inner one, so the inner must land
       first -- it does, because the inner alias is itself a declaration the
       outer's anchor walk then stops after }
  TE4 = TBox<TBox<TLater>>;

var
  ok, total: Integer;
  e1: TE1; h: THolder; e2: TE2; e3: TE3; e4: TE4;
  { 6. the use is in a VAR section, after the type section closed }
  e5: TBox<TA>;

procedure Check(cond: Boolean);
begin
  total := total + 1;
  if cond then ok := ok + 1;
end;

{ 7. and in a routine BODY }
function InBody: Integer;
var b: TBox<TLater>;
begin
  b := TBox<TLater>.Create;
  b.V := TLater.Create;
  b.V.K := 7;
  Result := b.V.K;
end;

begin
  ok := 0; total := 0;

  e1 := TE1.Create; e1.V := TLater.Create; e1.V.K := 1;
  Check(e1.V.K = 1);

  h := THolder.Create; h.F := TBox<TFwdArg>.Create;
  h.F.V := TFwdArg.Create; h.F.V.K := 2;
  Check(h.F.V.K = 2);

  e2 := TE2.Create; e2.V := TA.Create; e2.V.K := 3;
  Check(e2.V.K = 3);

  e3 := TE3.Create; e3.V := TB.Create; e3.V.M := 4;
  Check(e3.V.M = 4);

  e4 := TE4.Create; e4.V := TBox<TLater>.Create;
  e4.V.V := TLater.Create; e4.V.V.K := 5;
  Check(e4.V.V.K = 5);

  e5 := TBox<TA>.Create; e5.V := TA.Create; e5.V.K := 6;
  Check(e5.V.K = 6);

  Check(InBody = 7);

  writeln('total ok ', ok, ' / ', total);
end.
