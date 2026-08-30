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

end.
