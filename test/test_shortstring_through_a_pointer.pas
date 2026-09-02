program test_shortstring_through_a_pointer;
{ EVERY READER OF A FROZEN STRING'S LENGTH PREFIX, asserted as a RELATION.

  WHY READERS. Phase 2's call-site censuses all counted PXXWriteFrozenW --
  WRITERS -- and the defects are in readers. Comparison appears in no census;
  neither does Copy, Pos, or SetLength. A corrected count of the wrong
  population is still the wrong population, so this file enumerates the
  consumers instead: Length, comparison, indexing, Copy, Pos, SetLength,
  assignment out, the three parameter ABIs, and the write path -- each of them
  again through a typed-pointer deref, a record field, and an array element.

  WHY RELATIONS AND NOT VALUES. The defect class is a wrong prefix WIDTH, and
  the width is exactly what differs between the two frozen kinds. `Length(p^) = 5`
  would need a different expected value per mode; the raw bytes would need one
  per mode AND per target -- seven files to edit and an eighth to get wrong.
  `Length(p^) = Length(s)` is true under both widths on every backend, and is
  precisely what is false when a reader picks the wrong one. So the output is
  the same text everywhere and carries no per-target constant.

  WHAT THIS FILE IS FOR. Phase 2's aarch64 conversion fixed `Length(s)` and
  recorded the wrong answer it had been giving -- 122511465736197, which is
  0x6F6C6C654805: the length byte 5 followed by the characters of 'hello'.
  `Length(p^)` was still returning that same number afterwards, on aarch64 and
  on every other converted backend, because the fix closed the DIRECT shape of
  a two-shape bug and nothing looked for the sibling. Closing one shape of two
  is this feature's established failure mode, so the question this file has to
  answer is not "is the reported bug gone" but "WHICH READERS DOES THE FIX
  REACH". If one walker fix turns the whole matrix green, it was one bug with
  many faces; if it does not, the rows that stay red name the readers that
  carry their own width assumption. Nobody should have to guess which.

  ROW ORDER IS DELIBERATE AND IS NOT COSMETIC. Under a wrong width a reader
  gets a length in the hundreds of millions, so some rows do not return a wrong
  ANSWER -- they take the process down. Measured 2026-09-02 under
  -dPXX_SHORTSTRING: `r.f = s` segfaults on riscv32, and `Copy(p^,1,3)` reaches
  the allocator with that length and dies as `out of memory (heap arena mmap
  failed)` on x86-64. A crash truncates every row after it, so the rows are
  ordered safest-first and the known killers are LAST. Today's output is then
  the longest diagnostic the broken state can produce, and after the fix the
  ordering costs nothing.

  THIS IS A PROPERTY OF THE HARNESS AND NOT OF THIS FILE, so the next author
  should not have to rediscover it: a row that ends the process costs every row
  BEHIND it, which means a crashing test reports less the worse the state is --
  exactly backwards from what you want from a diagnostic. Any layout test whose
  failure mode is a length in the hundreds of millions has to be ordered, and
  the ordering has to be re-checked whenever a fix moves which row crashes. It
  moved once already: before 764dc3a30 the first killer was `assign from
  field`; after it, it is `compare field to literal`.

  Verified against FPC 3.2.2, which prints `total ok 28 / 28`.
  feature-p-implement-the-real-tyshortstring-byte-prefix-layout }

type
  TS10 = string[10];          { named because FPC refuses an inline string[N]
                                in a parameter list, and the oracle has to be
                                able to build this file }
  PS = ^TS10;
  TRec = record f: TS10; end;
  PRec = ^TRec;

var
  ok, total: Integer;

function PByteOf(base: Pointer; off: Integer): Byte;
{ One byte of a slot, read through the address. A raw read is the only thing
  that can see a character written at the wrong OFFSET -- every value-level
  assertion downstream of the corruption still passes. }
var q: ^Byte;
begin
  q := Pointer(PtrUInt(base) + PtrUInt(off));
  PByteOf := q^;
end;

procedure Chk(name: AnsiString; cond: Boolean);
begin
  Inc(total);
  if cond then begin Inc(ok); WriteLn('ok   ', name); end
  else WriteLn('FAIL ', name);
end;

var
  s, a: TS10;
  r: TRec;
  arr: array[0..2] of TS10;
  p: PS;
  pr: PRec;
  pa: PS;
  m: AnsiString;
  d, viaP: TS10;         { the store-shape pair: same start, two spellings }
  pv: PS;
  ch: Char;
  bi: Integer;
  sameBytes: Boolean;
  pfx: Integer;          { prefix width, DERIVED as SizeOf - capacity }

procedure ByVar(var v: TS10);
begin
  Chk('param var', Length(v) = Length(s));
end;

procedure ByConst(const v: TS10);
begin
  Chk('param const', Length(v) = Length(s));
end;

procedure ByVal(v: TS10);
begin
  Chk('param value', Length(v) = Length(s));
end;

begin
  ok := 0; total := 0;

  s := 'hello';
  r.f := 'hello';
  arr[1] := 'hello';
  p := @s;
  pr := @r;
  pa := @arr[1];

  { ---- READER: Length, through each way of naming the same buffer ---- }
  Chk('length deref', Length(p^) = Length(s));
  Chk('length field', Length(r.f) = Length(s));
  Chk('length field-through-pointer', Length(pr^.f) = Length(r.f));
  Chk('length array element', Length(arr[1]) = Length(s));
  Chk('length array-element pointer', Length(pa^) = Length(arr[1]));

  { ---- READER: indexing. The chars begin at base+prefix, so the index origin
    moves with the width; -7 was the spelling for the 8-byte word.

    `index deref` STILL FAILS on all four converted backends at 764dc3a30 --
    `p^[1]` reads a blank where the direct and field spellings both read 'h'.
    Measured, not inferred: the direct and field rows beside it are green in
    the same run, which is what makes this the index path through a DEREF
    rather than the index origin in general.
    bug-a-indexing-a-frozen-string-through-a-pointer-deref-reads-the-wrong-byte ---- }
  Chk('index direct', s[1] = 'h');
  Chk('index deref', p^[1] = s[1]);
  Chk('index field', r.f[1] = s[1]);

  { ---- READER: comparison against a LITERAL.

    THE ANNOTATION HERE WAS WRONG TWICE AND BOTH CORRECTIONS ARE THE POINT.

    It first said these rows would stay red on x86-64 and arm32 because the
    cause was OPERAND SELECTION -- a literal operand correct, a variable
    operand not, on the two backends with no named operand normaliser. That
    inference was sound-looking and false: "literal right, variable wrong" is
    exactly what a WIDTH bug produces, because variable-vs-literal IS the
    cross-width pair. A width-only fix turned both spellings green on both
    backends. The observation was good; the cause read off it was not.

    Measured at 764dc3a30 under -dPXX_SHORTSTRING, all four converted backends:
    `compare direct to literal` and `compare deref to literal` are GREEN.

    BUT `compare field to literal` IS NOT, AND IT IS A SEPARATE READER. Same
    command, same run: `r.f = 'hello'` SEGFAULTS on x86-64 and riscv32 and
    returns FALSE on aarch64 and arm32. A record FIELD compared against a
    literal reaches the comparison arm by a path the four-cause fix does not
    cover, so this is a fifth cause and not a leftover of the four.
    bug-a-comparing-a-frozen-record-field-to-a-literal-crashes-or-answers-false ---- }
  Chk('compare direct to literal', s = 'hello');
  Chk('compare deref to literal', p^ = 'hello');
  Chk('compare field to literal', r.f = 'hello');

  { ---- READER: assignment OUT of a frozen string ---- }
  a := p^;
  Chk('assign from deref', (Length(a) = Length(s)) and (a = s));
  a := r.f;
  Chk('assign from field', (Length(a) = Length(s)) and (a = s));
  m := s;
  Chk('assign to managed', (Length(m) = Length(s)) and (m = 'hello'));

  { ---- READER: the three parameter ABIs onto one buffer ---- }
  ByVar(s);
  ByConst(s);
  ByVal(s);

  { ---- READER: Pos and Copy on the DIRECT spelling. The deref form of Copy is
    an allocator killer and is held to the end. ---- }
  Chk('pos direct', Pos('ll', s) = 3);
  Chk('copy direct', Copy(s, 1, 3) = 'hel');

  { ---- THE WRITE PATH, printed rather than asserted, because a Boolean cannot
    see it. Write reads the count and the data ADDRESS off the prefix
    separately, so a half-converted reader prints the right NUMBER of bytes
    from the wrong place. The FIELD-WIDTH form goes through a shared runtime
    helper that reads the prefix itself -- a different code path from the
    width-0 form on five of seven backends, and the one that was broken on
    aarch64 after aarch64 was called complete. Both derefs must match their
    direct twin; the expected text carries all four. ---- }
  Write('write  <'); Write(p^);   Write('> <'); Write(s);   WriteLn('>');
  Write('writew <'); Write(p^:8); Write('> <'); Write(s:8); WriteLn('>');

  { ---- READER: SetLength IS ABSENT FROM THIS FILE ON PURPOSE, and its absence
    is a finding rather than an omission. It reads the prefix before it writes
    one and appears in no census, so it belongs in this matrix -- but riscv32
    refuses it outright: `target riscv32: standard builtin calls not supported
    in bare-metal stage 1 (builtin id 101)`. That is a MISSING FEATURE, not a
    width bug, it predates phase 2, and keeping the rows here would cost the
    whole matrix on riscv32 to assert something that is already a hard error.
    Pos and Copy were checked the same way and both compile there.
    bug-a-setlength-on-a-frozen-string-is-unsupported-on-riscv32 ---- }


  { ---- THE STORE SHAPE, ASSERTED AS BYTES AND NOT AS OUTPUT ----

    The walker is wrong on the WRITE side too, and this is the row that catches
    it: `p^ := c` writes the length byte at the narrow width and the CHARACTER
    at offset 8, so the slot reads back empty. Measured by franks-ab, and the
    corrupted memory is BYTE-IDENTICAL on x86-64, aarch64, arm32 and xtensa --
    two word sizes and four independently written backends. Identical bytes
    across those cannot be four codegen bugs; it is one shared walker.

    WHY BYTES AND NOT THE RENDERED STRING. This defect is leak-shaped: the slot
    is corrupted and everything downstream still runs, still prints and still
    passes. `s[0..6]` reads `1 0 0 0 0 0 0` and the program cheerfully prints
    `[ ]` -- an output-only row is the same instrument that certified aarch64
    complete while WriteLn(s:9) was broken. So the assertion reads the memory.

    WHY IT IS STILL A RELATION. The correct bytes DIFFER between the two modes
    (a 1-byte prefix puts the char at offset 1, an 8-byte one at offset 8), so
    no constant works. The invariant that holds under both is that the two
    SPELLINGS agree: a store through a deref must leave the slot byte-identical
    to the same store written directly. That is target-independent, mode-
    independent, and false exactly when the walker picks the wrong width. ---- }
  d := 'abcde'; viaP := 'abcde';
  pv := @viaP;
  ch := 'X';
  d := ch;                    { direct store }
  pv^ := ch;                  { the same store through a deref }
  sameBytes := True;
  for bi := 0 to SizeOf(d) - 1 do
    if PByteOf(@d, bi) <> PByteOf(@viaP, bi) then sameBytes := False;
  Chk('char store through deref writes a direct store''s bytes', sameBytes);
  Chk('char store through deref reads back', viaP = d);

  { THE RELATION ABOVE IS NOT ENOUGH ON ITS OWN, and this is not a hypothetical:
    measured on x86-64 under -dPXX_SHORTSTRING, `char store ... bytes` PASSES
    while the slot is corrupt, because the DIRECT store is broken the same way
    and two identically-wrong spellings compare equal. A relation between two
    things that can fail together is a guard that cannot fail.

    So the width is derived instead and the bytes are asserted ABSOLUTELY. The
    prefix size is not a constant that can be written here, but it is COMPUTABLE
    from the declaration: SizeOf(TS10) is prefix + 10, so the prefix is
    SizeOf - 10, which is 8 in the default mode and 1 under the flag without
    either number appearing in the source. The length byte then lives at offset
    0 under both, and the first character at offset `pfx` -- which is exactly
    what a walker that picks the wrong width gets wrong. }
  pfx := SizeOf(d) - 10;
  Chk('direct char store puts the length at offset 0', PByteOf(@d, 0) = 1);
  Chk('direct char store puts the char at offset pfx', PByteOf(@d, pfx) = Ord('X'));
  Chk('deref char store puts the length at offset 0', PByteOf(@viaP, 0) = 1);
  Chk('deref char store puts the char at offset pfx', PByteOf(@viaP, pfx) = Ord('X'));

  d := 'abcde'; viaP := 'abcde';
  pv := @viaP;
  d := 'wo';
  pv^ := 'wo';                { and the string-valued store }
  sameBytes := True;
  for bi := 0 to SizeOf(d) - 1 do
    if PByteOf(@d, bi) <> PByteOf(@viaP, bi) then sameBytes := False;
  Chk('string store through deref writes a direct store''s bytes', sameBytes);

  { ---- THE TWO KNOWN KILLERS, LAST. Both take the process down rather than
    returning a wrong answer, so every row above would be lost behind them. ---- }

  { a field compared against a VARIABLE -- segfaults on riscv32 under the flag }
  Chk('compare field to variable', r.f = s);

  { Copy through a deref -- reaches the allocator with a length in the hundreds
    of millions and dies "out of memory" on x86-64 under the flag }
  Chk('copy deref', Copy(p^, 1, 3) = 'hel');

  WriteLn('total ok ', ok, ' / ', total);
end.
