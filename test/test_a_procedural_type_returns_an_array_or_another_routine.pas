{ A procedural TYPE's signature row must record the same facts about its return
  type that an ordinary routine header records, or an indirect call cannot say
  what it got back.

  Three shapes, each with its DIRECT-call control on the next row, because each
  was measured working through a direct call throughout -- which is what says
  the defect is the signature path and not the feature.
  bug-p-a-procedural-type-cannot-return-an-array-or-another-procedural-type

  ROWS G, H AND I ARE NOT DECORATION. Indexing was refused OUTRIGHT (`expected
  ')' before '['`), but the whole-value assignment `b := fq(4)` COMPILED and
  answered `4310400 0 0` where fpc answers `104 204 304` -- silently, and on pin
  v404 too. A file that only asserted the indexed spellings would have gone
  green with that still broken, because the refusal is the loud half and the
  silent half is the one that ships. Every element is printed for the same
  reason: element 0 alone passes while 1 and 2 are garbage.

  .expected is fpc 3.2.2's own output, byte for byte. }
program test_a_procedural_type_returns_an_array_or_another_routine;

type
  TIA    = array of Integer;
  TA3    = array[0..2] of Integer;
  TInner = function(n: Integer): Integer;
  TF     = function(n: Integer): TIA;      { dyn-array return }
  TF3    = function(k: Integer): TA3;      { fixed-array return }
  TOuter = function: TInner;               { procedural return }
  TRecOfFn = record fn: TF; end;           { …the same signature as a FIELD }

function MkIA(n: Integer): TIA;
begin
  SetLength(Result, 3);
  Result[0] := n; Result[1] := n + 1; Result[2] := n + 11;
end;

function MkA3(k: Integer): TA3;
begin
  MkA3[0] := k + 100; MkA3[1] := k + 200; MkA3[2] := k + 300;
end;

function Inner(n: Integer): Integer;
begin
  Inner := n + 1;
end;

function MkOuter: TInner;
begin
  MkOuter := @Inner;
end;

var
  fp: TF; fq: TF3; fo: TOuter;
  da: TIA; sa: TA3; fn: TInner;
  rc: TRecOfFn; av: array[0..1] of TF;

begin
  fp := @MkIA; fq := @MkA3; fo := @MkOuter;

  { the three the ticket names, indirect }
  WriteLn('A ', fp(3)[2]);
  WriteLn('C ', fq(4)[2]);
  WriteLn('E ', fo()(41));

  { …and each one's DIRECT-call control, which passed before the fix }
  WriteLn('B ', MkIA(3)[2]);
  WriteLn('D ', MkA3(4)[2]);
  WriteLn('F ', MkOuter()(41));

  { the WHOLE value through the proc var — the silent half }
  da := fp(3);
  WriteLn('G ', da[0], ' ', da[1], ' ', da[2]);
  sa := fq(4);
  WriteLn('H ', sa[0], ' ', sa[1], ' ', sa[2]);

  { a procedural result NOT called in place: `fo()` is still a value.

    THE ORACLE IS `fpc -Mobjfpc`, NOT `-Mdelphi`, AND THIS ROW IS WHY: fpc 3.2.2
    raises an INTERNAL COMPILER ERROR on `fn := fo()` under -Mdelphi --
    "Compilation raised exception internally" at this line, no output at all --
    and compiles the identical program under -Mobjfpc. Isolated to this one
    statement, not assumed from the line number the first run reported. pxx's
    default mode is the objfpc-shaped one and every procedural assignment here
    is written with @, so -Mobjfpc is the matching oracle rather than a weaker
    one. Nothing is worked around in the compiler for this. }
  fn := fo();
  WriteLn('I ', fn(41));

  { index 0, because 0 is where a scalar store leaves a plausible number }
  WriteLn('J ', fq(4)[0]);
  WriteLn('K ', fp(3)[0]);

  { THE SAME CALL THROUGH A FIELD AND AN ELEMENT, which are DIFFERENT BUILDERS.
    A proc-VARIABLE call goes through BuildIndirectCallAST and reaches the shared
    suffix handoff; a field and an array element each build their AN_CALL_IND
    inline at their own site and land in the postfix loop's index arm instead.
    That arm excluded AN_CALL_IND on a stated reason that was false, so `rc.fn()[1]`
    answered `IR_UNSUPPORTED ... kind 53` while `fp(3)[1]` on the identical
    signature was correct. Rows A..K would all be green with these two broken:
    one construct, three builders, and only one of them was on the fixed path. }
  rc.fn := @MkIA;
  WriteLn('L ', rc.fn(3)[1]);
  av[0] := @MkIA;
  WriteLn('M ', av[0](3)[1]);
end.
