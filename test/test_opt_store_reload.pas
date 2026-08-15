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
end.
