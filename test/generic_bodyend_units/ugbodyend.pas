{ The subject of test_generic_body_end_counting. It MUST be a UNIT: the defect
  lives in ParseUnit's implementation loop, and the same declarations inside a
  PROGRAM are unaffected -- the first draft of this test was a program and the
  PRE-FIX compiler printed the correct answer for it. }
unit ugbodyend;
{$mode objfpc}

interface

type
  generic TBox<T> = class
    function TryFinally: Integer;
    function TryExcept: Integer;
    function WithAsm: Integer;
    function LocalRecord: Integer;
    function CaseStillWorks(k: Integer): Integer;
    function Tail: Integer;
  end;

{ The generic-FUNCTION arms. Until bug-p-a-generic-function-cannot-be-declared-
  in-a-unit was fixed these could not exist: a `generic function` was accepted at
  PROGRAM level and refused in BOTH of a unit's sections, and at program level
  the pre-fix counter is already correct. So the function-side copy of the
  body-extent counter -- corrected in the same change as the method-side one --
  had no positive control and could not be given one.

  WHERE THE CALL SITE IS, IS THE WHOLE TEST. The first draft of these arms
  called them from wrappers in this unit's own implementation and PASSED with
  the counter reverted to [tkBegin, tkCase] -- a guard that could not fail. The
  truncated template ends one `end` early, and the specialization for an in-unit
  use is spliced at exactly the position that leftover `end` occupies, so the
  two cancel and the routine parses correctly by accident. Only a call from the
  PROGRAM BODY, spliced at the program's `begin` and nowhere near the leftover,
  exposes it -- and then this unit fails to compile with `unexpected token in a
  unit implementation section` at the routine BELOW the defect. So the
  specializing use of these two lives in test_generic_body_end_counting.pas,
  deliberately, and GenFuncInUnit below is the passing CONTROL for the other
  half. }
generic function GFTryFinally<T>(a: T): T;
generic function GFTryExcept<T>(a: T): T;
function GenFuncInUnit: Integer;
function GenFuncTail: Integer;

implementation

{ ---- the two MEASURED regression arms: each alone makes the pinned binary
       fail, and each closes a block with an `end` the body-extent counter in
       pasparser_generic.inc did not know about ---- }

function TBox.TryFinally: Integer;
begin
  Result := 0;
  try
    Result := 4;
  finally
    Result := Result + 5;
  end;
end;

function TBox.TryExcept: Integer;
begin
  Result := 0;
  try
    Result := 9;
  except
    Result := 1;
  end;
end;

{ `nop` on purpose -- it exists on every target we emit for. FPC has no opinion
  to offer on this arm: it refuses assembler blocks inside generics outright, so
  the expected 7 is ours, and the arm's evidence is the pinned binary failing. }
function TBox.WithAsm: Integer;
begin
  Result := 1;
  asm
    nop
  end;
  Result := 7;
end;

{ ---- CONTROLS: shapes that already worked and must keep working ---- }

{ A local `record` type is NOT a regression arm and must not be read as one:
  the pre-fix binary compiles it correctly. The body scanner skips to the first
  `begin` before it starts counting, and a local type section sits before that,
  so `record` can never reach the counter. It is here because that is a fact
  about this code that took an isolation to establish, and the next person to
  "fix the sibling by copying its token set" should find it already answered. }
function TBox.LocalRecord: Integer;
type TR = record a, b: Integer; end;
var r: TR;
begin
  r.a := 2; r.b := 3;
  Result := r.a + r.b;
end;

{ the two openers the counter always knew, so a fix cannot quietly drop them }
function TBox.CaseStillWorks(k: Integer): Integer;
begin
  Result := 0;
  case k of
    1: Result := 9;
    2: begin Result := 8; end;
  end;
end;

{ every arm above needs a routine AFTER it: a truncated body only becomes
  damage when something follows it to be mis-parsed. }
function TBox.Tail: Integer;
begin
  Result := 100;
end;

{ ---- the generic-FUNCTION copy of the same counter, in the only place it can
       be reached: a unit implementation. Same two block openers, same shape,
       and each is a MEASURED regression arm -- reverting the counter to
       [tkBegin, tkCase] makes this unit fail to compile at its last line. ---- }

generic function GFTryFinally<T>(a: T): T;
begin
  Result := a;
  try
    Result := a + a;
  finally
    Result := Result + 1;
  end;
end;

generic function GFTryExcept<T>(a: T): T;
begin
  Result := a;
  try
    Result := a + a;
  except
    Result := 0;
  end;
end;

{ CONTROL, not a regression arm: an in-unit use of a `try`-bodied generic
  function passes even with the counter reverted, because the specialization is
  spliced right where the truncated body left its `end` behind. Here so the next
  person to add an arm here does not repeat the draft that could not fail. }
function GenFuncInUnit: Integer;
begin
  Result := specialize GFTryExcept<Integer>(3);
end;

{ the routine AFTER the generic definitions: a truncated body only becomes
  damage when something follows it to be mis-parsed. With the counter reverted
  the diagnostic lands HERE, not at the defect. }
function GenFuncTail: Integer;
begin
  Result := 200;
end;

end.
