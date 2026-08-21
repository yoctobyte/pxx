{ -O3 store->reload elimination (feature-opt-accumulator-value-tracker).

    x := a + b;    { mov [x], rax }
    y := x * 2;    { the reload is gone — rax already holds it }

  Every value here must be IDENTICAL at -O0 and -O3; that differential is the
  cheap oracle for exactly the miscompile class this pass can cause. Three
  things are being asserted at once:

  1. WIDTH. The store wrote only the low TypeSize bytes of rax, so the reload
     is replaced by a re-extension of rax, not by nothing. `big` is 2^32+5, so
     an Integer destination whose high bits were NOT re-cut would print
     4294967301 instead of 5 — and the same for the sign/zero-extending 1- and
     2-byte cases, which is why ShortInt(200) and Word(70000) are here.

  2. THE NEGATIVE CASE the whole ticket exists for. `y := 5 * x` evaluates the
     CONST left leaf first at -O0/-O1, so MovRaxImm(5) has already clobbered
     rax by the time the load runs. The mark must NOT be set — a tracker that
     knows only "rax held x after the store" multiplies by 5 and prints
     garbage.

  3. THE INVARIANT: a load may be marked only when NOTHING AT ALL is emitted
     between the store and it. The WriteLn between the store and the use is
     that test — it is a call, so the run ends there.

  ParamCount keeps every value out of reach of constant folding (it is 0 at
  run time, so the printed numbers are stable); without it -O3 folds the whole
  program to literals and the test asserts nothing.

  Expected values are FPC 3.2.2's on this same source. }
program test_opt_store_reload;
var
  big, r: Int64;
  i: Integer;
  c: ShortInt;
  w: Word;
  u: LongWord;
  p: Pointer;
  q: PtrUInt;
  bo: Boolean;
  arr: array[0..1] of Integer;
  rec: record f: Integer; end;
  pi: ^Integer;
begin
  big := 4294967296 + 5 + ParamCount;

  { 1. widths — the re-extension table }
  i := Integer(big);                r := i * 2;  WriteLn('int   ', i, ' ', r);
  c := ShortInt(200 + ParamCount);  r := c * 2;  WriteLn('short ', c, ' ', r);
  w := Word(70000 + ParamCount);    r := w * 2;  WriteLn('word  ', w, ' ', r);
  u := LongWord(big);               r := u * 2;  WriteLn('ulong ', u, ' ', r);
  r := big + ParamCount;            r := r * 2;  WriteLn('int64 ', r);

  { pointer-width slot: no extension at all, the reload just disappears }
  p := @big;                        q := PtrUInt(p) - PtrUInt(@big);
  WriteLn('ptr   ', q);

  { 2. const LEFT operand — the reload must STAND }
  i := Integer(big);                r := 5 * i;  WriteLn('constl', ' ', r);

  { 3. a call between the store and the use ends the run }
  i := Integer(big) + 1;
  WriteLn('between');
  r := i * 2;                                    WriteLn('after  ', r);

  { 4. THE STATEMENT AFTER THE STORE IS A BRANCH, not another store
    (feature-opt-store-reload-elimination). A conditional branch reaches its
    condition before emitting anything, so the same run continues into it —
    but the fused compare-into-branch has its OWN operand-order chain, which
    is why IRStmtFirstEvaluated exists beside IRFirstEvaluated.

    Every case below is a WIDTH oracle, not just a control-flow one: the
    truncated store and the untruncated rax straddle the comparison's
    threshold, so a missing re-extension flips the branch and prints the
    other word. ShortInt(200) is -56 (rax holds 200), Word(70000) is 4464
    (rax holds 70000), LongWord(2^32+5) is 5 (rax holds 2^32+5). }
  c := ShortInt(200 + ParamCount);
  if c < 0 then WriteLn('br shortint neg') else WriteLn('br shortint POS');
  w := Word(70000 + ParamCount);
  if w > 60000 then WriteLn('br word BIG') else WriteLn('br word small');
  u := LongWord(big);
  if u > 100 then WriteLn('br ulong BIG') else WriteLn('br ulong small');

  { a NON-fused condition: the branch tests a Boolean value, so the mirror
    falls through to the ordinary value-tree answer }
  bo := (Integer(big) > 3) and (ParamCount = 0);
  if bo then WriteLn('br bool true') else WriteLn('br bool false');

  { the const-LEFT negative case again, in branch position: `5 > i` puts a
    leaf sym on the RIGHT, so the fusion loads the CONST first and the reload
    must stand }
  i := Integer(big);
  if 5 > i then WriteLn('br constl le') else WriteLn('br constl GT');

  { a call between the store and the branch ends the run, exactly as it does
    between two stores }
  c := ShortInt(200 + ParamCount);
  WriteLn('br between');
  if c < 0 then WriteLn('br after neg') else WriteLn('br after POS');

  { 5. the statement after the store writes through an ADDRESS — an array
    element, a record field, a pointer deref. IR_STORE_MEM's generic arm
    evaluates the VALUE first and computes the destination address after it,
    so the run continues into it exactly as it does into another plain store.
    Same width oracle: ShortInt(200) is -56, so -112 here and 400 if the
    re-extension went missing. }
  c := ShortInt(200 + ParamCount);
  arr[0] := c * 2;
  c := ShortInt(200 + ParamCount);
  rec.f := c * 2;
  c := ShortInt(200 + ParamCount);
  pi := @arr[1];
  pi^ := 0;                 { the store to pi^ is not the one under test }
  c := ShortInt(201 + ParamCount);
  pi^ := c * 2;
  WriteLn('mem   ', arr[0], ' ', rec.f, ' ', arr[1]);
end.
