{ SPDX-License-Identifier: MPL-2.0 }
{ SHARED COMPILER UTILITIES — belonging to no frontend and no backend.

  Small helpers the whole compiler uses. The bar for landing here is that a
  build with ANY single frontend or backend omitted still needs it
  (feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets);
  anything one language or one target owns belongs in that language's or that
  target's file instead.

  Included immediately after lexer.inc — not earlier, which is where it wants
  to go. AppendChar, an equally general string helper, is itself defined in
  lexer.inc, so a utility file placed before it cannot use it. That is the same
  finding one level down and is left alone deliberately: moving AppendChar
  touches the two FPC-vs-self-host variants at lexer.inc:331/352 and is not
  part of a mechanical move. }

{ The compiler's own IntToStr. The `A` is for AnsiString, not for Ada — its
  body lived in aparser.inc (the ~460-line Ada skeleton) until 2026-08-19,
  which meant the Pascal parser, the NilPy parser, the C parser and the C
  preprocessor all depended on the Ada frontend being compiled in. Omitting Ada
  was the only reason anybody noticed: `-dPXX_NO_ADA` left one unsolved forward
  and nothing else. A shared utility marooned in a skeleton frontend is
  invisible while every frontend is always built, which is exactly why the
  omission defines keep finding things reading the code does not.

  Until 2026-08-21 a NEGATIVE n yielded the EMPTY STRING — `while n > 0` never
  entered, so AIntToStr(-5) was '', with no sign and no digits. Every caller
  passes a count, an index, a parameter number or a version, so the failure
  mode was never a wrong number: it was a diagnostic with a HOLE in it
  ('takes at most  arguments'), which reads as a formatting slip rather than a
  value bug. That is why it survived ~40 call sites.
  bug-a-aintostr-returns-empty-for-negative-numbers

  The digits are accumulated on the NEGATIVE side, which is the whole trick:
  negating first would work for every input except Low(Integer), whose
  magnitude has no positive representation, so `n := -n` on it silently yields
  Low(Integer) again and the loop never terminates. There is no such asymmetry
  going downward — `n div 10` truncates toward zero, so the magnitude only
  shrinks. Pascal's `mod` takes the sign of the dividend, hence the -(n mod 10)
  to get a 0..9 digit.

  The '-' is appended LAST because the buffer is built backwards and reversed
  below, which puts the sign in front. }
function AIntToStr(n: Integer): AnsiString;
var rev, res: AnsiString; i: Integer; neg: Boolean;
begin
  neg := n < 0;
  if not neg then n := -n;      { work in the negative half — see above }
  rev := '';
  if n = 0 then AppendChar(rev, '0')
  else
    while n < 0 do
    begin
      AppendChar(rev, Chr(Ord('0') - (n mod 10)));
      n := n div 10;
    end;
  if neg then AppendChar(rev, '-');
  res := '';
  for i := Length(rev) downto 1 do AppendChar(res, rev[i]);
  Result := res;
end;

function AInt64ToStr(n: Int64): AnsiString;
{ AIntToStr's 64-bit twin, and it exists for a reason worth stating: the first
  caller is a diagnostic about a value being OUT OF RANGE, and handing such a
  value to the 32-bit version truncates it -- `4294967297` prints as `1`, so the
  message would have read "set element 1 is outside a set's 0..255 domain".
  A message that range-truncates the value it is complaining about is the
  instrument-that-lies-by-being-correct-about-something-else in its purest
  form: the truncation is exactly the defect class the diagnostic exists to
  report, performed by the report.

  Same negative-side accumulation as AIntToStr and for the same reason -- see
  its header; Low(Int64) has no positive representation either. }
var rev, res: AnsiString; i: Integer; neg: Boolean;
begin
  neg := n < 0;
  if not neg then n := -n;      { work in the negative half — see AIntToStr }
  rev := '';
  if n = 0 then AppendChar(rev, '0')
  else
    while n < 0 do
    begin
      AppendChar(rev, Chr(Ord('0') - Integer(n mod 10)));
      n := n div 10;
    end;
  if neg then AppendChar(rev, '-');
  res := '';
  for i := Length(rev) downto 1 do AppendChar(res, rev[i]);
  Result := res;
end;

function RealTypeKind: TTypeKind;
{ What the type name `Real` MEANS on this target: the native float depth.
  xtensa and riscv32 have no hardware double, and `Real` being single-precision
  there is DELIBERATE — a long-settled dialect decision, not a target test that
  forgot a profile. Documented in docs/language/types.md; see
  bug-a-real-is-single-on-hosted-riscv32, which read it as a bug and is
  rejected.

  It is a routine because the rule was written out twice and the two copies
  DISAGREED. BuiltinScalarTypeKind (the declaration path) had it target-keyed,
  so `var r: Real` was 4 bytes on riscv32 and the arithmetic was genuinely
  single-precision. BuiltinTypeNameTk — the table whose own header says "one
  table, so the next builtin type cannot be present in half the compiler" —
  hard-wired tyDouble, and that is the table SizeOf consults. So `SizeOf(Real)`
  answered 8 for a variable that occupied 4: a wrong size reaching GetMem and
  Move, silently, on the one target where it was least likely to be noticed.
  bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets }
begin
  if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
    RealTypeKind := tySingle
  else
    RealTypeKind := tyDouble;
end;

function BareStringKind: TTypeKind;
{ What the type name `string` MEANS in this build: the managed tyAnsiString by
  default, the legacy frozen tyString under `-uPXX_MANAGED_STRING`.

  Same routine, same reason, same bug as RealTypeKind directly above -- one type
  over. It lived in pasparser_decl.inc serving TWO callers whose header comment
  already said they MUST agree, while BuiltinTypeNameTk (the table SizeOf
  consults) hard-wired tyString beside a neighbouring arm that consults the
  define. So `SizeOf(string)` answered 8 on i386, arm32 and riscv32 for a
  variable, record field and array element that every one of them occupied 4 --
  pxx disagreeing with ITSELF inside one program, `SizeOf(string) <> SizeOf(v)`,
  and a wrong size reaching GetMem and Move on exactly the targets where it is
  least likely to be noticed.

  Moved HERE rather than forward-declared because this is where the sibling
  one-answer helper already lives and every caller is downstream of util.inc:
  the declaration path, SizeOf's table, the resourcestring path and the operator
  -overloading table can now all ask the same question.
  bug-p-sizeof-string-disagrees-with-the-storage-string-actually-gets }
begin
  { {$H-} / {$LONGSTRINGS OFF} wins over both: it asks for the CLASSIC inline
    256-byte ShortString, which is what fpc's own compiler sources declare (line
    3 of fpcdefs.inc) and what every bare `string` in that corpus means.

    Read POSITIONALLY, off the token being parsed, not from HMinusVal -- the
    directive runs in the LEX pass, so the global holds the LAST {$H} in the
    file by the time any declaration parses, and a file with a single directive
    cannot tell the two readings apart. Same discipline and same reason as
    TokPackEnum. feature-p-h-minus-makes-a-bare-string-a-shortstring }
  if (TokPos > 0) and (TokPos - 1 < Length(TokHMinus)) and TokHMinus[TokPos - 1] then
    BareStringKind := tyShortString
  else if PasDefineExists('PXX_MANAGED_STRING') then BareStringKind := tyAnsiString
  else BareStringKind := tyString;
end;


function TargetIsEspClass: Boolean;
{ True for the ESP-class bare-metal targets — the ones that have no hosted OS
  under them and therefore no full RTL: EITHER ESP ISA under `--esp-profile=bare`,
  and neither of them otherwise. BOTH are dual-role — riscv32 is bare ESP32-C3 or
  hosted Linux, xtensa is bare or IDF/FreeRTOS-linked — which is exactly why the
  profile has to be part of the test and why writing it out by hand is a trap.
  (Until 2026-08-27 the body said xtensa ALWAYS; see the note in it.)

  It was written out by hand, 24 times, all identical:

    (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot))

  20 in pasparser_prog.inc, 2 in pasparser_proc.inc, 1 in cparser.inc and 1 in
  compiler.pas's own body, every one of them guarding "may I pull this RTL
  unit". The last three were found by the ticket's grep-for-the-sibling pass
  after the first 21 were replaced, and they are the argument in miniature: the
  C frontend and the -Fu default-path setup ask the identical question and had
  drifted into their own copies, each with its own comment saying "same guard as
  the Pascal default-RTL pull" — the sameness was documented in prose and not in
  code. Adding a target means editing all 24 or being silently wrong at
  whichever one is missed — and being wrong here does
  not crash, it silently drags an uncompilable unit into a bare-metal build or
  silently omits Str/Val from a hosted one. Found while scoping
  feature-a-riscv64-as-a-hosted-first-class-target, where it is a prerequisite.

  NOT to be confused with the OTHER spelling in the tree,
  `(TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32)` with no
  profile test (13 sites: emit.inc, elfwriter.inc, exception_emit.inc,
  pasparser_decl.inc, lexer.inc, pasparser_prog.inc). Those are deliberately
  left alone: they look like one concept and are several — "no DWARF", "the
  only two --emit-obj targets", "Real is Single", "no hardware FPU" — so
  collapsing them into one predicate would assert a sameness that is not there.
  They are also where riscv64 must NOT simply be added: each needs its own
  answer. The list is in the riscv64 ticket. }
begin
  { PROFILE, not ISA. This used to read `(TargetArch = TARGET_XTENSA) or
    ((TargetArch = TARGET_RISCV32) and EspBareBoot)` — "xtensa MEANS bare
    metal", which was true before the IDF profile existed and became wrong the
    moment it did, in the worst possible place: xtensa is the ESP32/S2/S3, and
    the asymmetry locked it out of the one profile where FreeRTOS tasks, IDF
    drivers, VFS file I/O and sockets live, while riscv32 under the same profile
    got all of it. Same program, same flags, measured 2026-08-27:

      hello  --platform=esp  esp32c3 (riscv32) 239120B / 169 procs
                             esp32s3 (xtensa)   47375B /  90 procs
      timer  --platform=esp  esp32c3           345572B / 288 procs
                             esp32s3            49731B / 101 procs

    and `examples/esp32/net-c3` has no `net-s3` counterpart at all.

    The question this predicate answers is "is there an OS under this program",
    and the flag that answers it is `--esp-profile=bare` — for BOTH ESP ISAs.
    EspBareBoot is already validated to riscv32/xtensa only (compiler.pas), so
    the ISA test is redundant as well as wrong; it is kept for clarity about
    which targets can reach the state at all.
    feature-a-complete-the-builtin-unit-on-the-esp-class-targets }
  Result := EspBareBoot and
            ((TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32));
end;

function SoftFloatMissing(const nm: AnsiString): AnsiString;
{ The one wording for "a __pxx_* soft-float kernel was not registered". Twelve
  sites across ir_codegen_riscv32.inc and ir_codegen_xtensa.inc raised this, all
  spelled `compiler error: <nm> not found (uses softfloat?)` — which reads as an
  INTERNAL FAULT for what is an ordinary user program on a target with no FPU,
  and whose parenthesised hint is a question rather than an instruction.

  It is now rare by construction: both frontends pull `softfloat` on demand when
  they see a float in the source (ParseProgram / the C driver). What is left is
  the scan's blind spot — a float that reaches codegen through a name the token
  scan cannot see, e.g. `var x: TFloatAliasFromSomeUnit`. That case is fixable by
  the person in front of the compiler, so say how instead of claiming a fault.
  bug-a-esp32c3-bare-profile-cannot-find-the-softfloat-repack-helper }
begin
  Result := 'this target has no FPU and the soft-float kernel ' + nm +
            ' is not linked; add `uses softfloat` to the program';
end;

function Low32(v: Int64): Int32;
{ The low 32 bits of v, as a signed 32-bit value -- the 32-bit immediate a
  32-bit target actually loads.
  The truncation is DELIBERATE and value-preserving: IR integer constants are
  always stored Int64, so a Cardinal `$FFFFFFFF` arrives as 4294967295, which
  is outside Int32's range but whose low 32 bits are exactly the bit pattern
  the target must load. Verified three ways -- arm32 under qemu, native pxx,
  and fpc all print 4294967295 for `c: Cardinal; c := $FFFFFFFF` -- so this is
  a reinterpretation, not a loss.

  It exists because that narrowing was IMPLICIT at every site, which builds
  fine and runs fine and makes the range-checked seed unrunnable: `-Cr` checks
  the assignment into an `Int32` parameter and aborts. Writing the cast out
  says "yes, on purpose" in the one place where someone can also read WHY, and
  it makes the class greppable -- the four 32-bit backends hold ~130 `IRIVal`
  references between them and the chain of trapping ones is only discoverable
  one abort at a time.
  bug-a-the-range-checked-seed-traps-on-deliberate-wraparound-arithmetic }
begin
  Result := Int32(v and $FFFFFFFF);
end;

{ Append a string to the shared TokChars pool and return its offset.

  Every frontend that mints a SYNTHETIC identifier or string token needs this,
  because TokChars is the one pool the AST's SOffset/SLen pairs point into. It
  lived in pyparser.inc as `PyStoredName` until 2026-08-31, which is why
  cparser.inc:2000 (`__func__`) and six sites in pasparser_expr.inc called into
  the NilPy frontend for it -- the single frontend-to-frontend dependency in the
  compiler, and it reads as impossible right up until someone trips on it. The
  comment at the C site had already noticed and said so in prose: "a generic
  ... helper (despite its name/home in pyparser.inc)". A note is not a fix.

  THREE MORE COPIES OF THIS EXACT BODY REMAIN, differing only in their overflow
  message: TokCharsAppend (pasparser_class.inc), RStoredName (rparser.inc, and
  it tells an Erlang or Zig program that IT is Rust) and BStoreChars
  (bparser.inc). Folding them is refactor-a-seven-frontends-borrow-rust-parser-
  helpers, which already owns that work and already prescribes this name -- so
  this is deliberately the move and not the fold, and the fold has one target
  instead of two. }
function StoredName(const s: AnsiString): Integer;
var i: Integer;
begin
  Result := TokCharLen;
  for i := 1 to Length(s) do
  begin
    if TokCharLen >= STRING_CAP then Error('token char buffer overflow');
    TokChars[TokCharLen] := s[i];
    Inc(TokCharLen);
  end;
end;

{ THE .data IMAGE GROWS ON DEMAND. `Data` was `array[0..MAX_DATA-1] of Byte`
  (2 MB reserved in bss), and MAX_DATA was a REACHABLE ceiling: measured
  2026-09-06, a C program with 52200 distinct short string literals answers
  `error: data overflow` while 52000 compiles at data=2092792. That is not an
  exotic input -- every string literal costs 32 bytes of managed-string header
  plus its 8-aligned text (see InternStr), so 2 MB is ~52k literals and nothing
  else in .data.

  WHY THE STRING TABLE'S OWN CAP COULD NEVER FIRE, which is the reason these two
  tables move together in the ticket even though no constant is shared:
  MAX_STRS is 65536 and every entry costs at least 40 bytes of Data, so DataLen
  overflowed at ~52108 entries and `Error('string table overflow')` in InternStr
  was unreachable -- a guard that cannot fail. Converting Data makes it reachable
  for the first time. The coupling is arithmetic BETWEEN two independent
  constants, so the ticket's prescribed `grep the MAX_ name` cannot see it:
  the two tables share a resource, not an identifier.

  Callers keep their own `DataEnsure(n)` immediately before their own write, so
  the guard stays exactly where the overflow check was and nothing is hoisted.
  feature-dynamic-compiler-tables }
procedure DataEnsure(n: Integer);
var oldCap, i: Integer;
begin
  if DataLen + n <= DataCap then Exit;
  oldCap := DataCap;
  if DataCap = 0 then DataCap := 65536;
  while DataCap < DataLen + n do DataCap := DataCap * 2;
  SetLength(Data, DataCap);
  { Bytes at or past DataLen ARE read before being written: symtab.inc's
    static-array initialiser path aligns `base` up from DataLen and never writes
    the padding, and the old fixed array was bss, i.e. zero by construction.
    SetLength is specified to zero new elements; this loop states the property
    rather than inheriting it, because a garbage alignment byte lands in .data
    silently and no assertion in this compiler reads .data padding. }
  for i := oldCap to DataCap - 1 do Data[i] := 0;
end;

{ The relocation table and its TWO PARALLEL COLUMNS grow as one. FixupPCRel and
  FixupPicDelta are indexed by the same fixup number as Fixups, so a grow that
  moved one and not the others is the identical defect to a compaction that
  does -- and this repo has already had one of those, silently, in
  compiler.pas's DATAREF_DROP arm (a8bfcb695). Keeping the three SetLengths in
  one procedure is the point: there is no site where you can grow the table
  without growing the columns, because there is only one site.

  MAX_FIXUPS was 131072 and it was reachable -- 200000 short C string literals
  answered `error: fixup overflow`, which is how this family was found at all:
  by pushing an input past the string-table cap that had just been lifted, and
  reading whatever stopped it next. feature-dynamic-compiler-tables }
procedure FixupEnsure;
begin
  if FixCount < FixCap then Exit;
  if FixCap = 0 then FixCap := 8192 else FixCap := FixCap * 2;
  SetLength(Fixups, FixCap);
  SetLength(FixupPCRel, FixCap);
  SetLength(FixupPicDelta, FixCap);
end;

{ ---- SEMANTIC IDENTITY: the accessors ------------------------------------

  The encoding, the families and the reason the non-enum families live in
  NEGATIVE space are all documented at SEM_NONE in defs.inc. These are the only
  things that know it: nothing outside this block may compare a SemId against a
  number, because the whole value of the negative layout is that an unwidened
  reader's `>= 0` keeps meaning "is an enum" without being told.

  Here rather than in symtab.inc because they are pure arithmetic on one
  Integer -- no symbol table, no enum table, no parser state -- and every
  frontend's declaration path needs them. SemKindMatches, the WINDOW guard, is
  NOT here: it has to ask EnumStorageTypeKind, so it lives beside
  EnumKindMatches in pasparser_decl.inc.
  decide-how-a-type-carries-an-identity-its-kind-cannot-hold }

{ The identity of a value of enum type `etid`. The identity function on
  purpose: an enum SemId IS its enum type index, which is what makes every
  channel that used to hold only enum ids able to hold a SemId unchanged. }
function SemEnum(etid: Integer): Integer;
begin
  if etid < 0 then Result := SEM_NONE else Result := etid;
end;

function SemIsEnum(sem: Integer): Boolean;
begin
  Result := sem >= 0;
end;

{ The enum type index a SemId names, or -1 for every other family. This is the
  accessor an OLD enum-only reader turns into when it is widened; it is also
  what makes widening optional, since `sem >= 0` already answers the same
  question for a reader that has not been touched. }
function SemEnumOf(sem: Integer): Integer;
begin
  if sem >= 0 then Result := sem else Result := -1;
end;

{ The identity of a C-ABI boolean `width` bytes wide -- ByteBool 1, WordBool 2,
  LongBool 4, QWordBool 8. Its KIND stays an integer of that width, deliberately
  (see BuiltinScalarTypeKind): the width is right and it is the booleanness that
  had nowhere to live. }
function SemBool(width: Integer): Integer;
begin
  if width <= 0 then Result := SEM_NONE else Result := SEM_BOOL_BASE - width;
end;

function SemIsBool(sem: Integer): Boolean;
begin
  Result := sem < SEM_BOOL_BASE;
end;

{ Storage width in bytes of a sized-boolean SemId, else 0. }
function SemBoolWidth(sem: Integer): Integer;
begin
  if sem < SEM_BOOL_BASE then Result := SEM_BOOL_BASE - sem else Result := 0;
end;

{ The TTypeKind a sized boolean of `width` travels in -- its layout, with the
  booleanness carried beside it. SIGNED, and that is not cosmetic: FPC's
  `Ord(ByteBool(True))` is -1 because True is stored all-bits-set and read back
  through a SIGNED ordinal, which is the C-ABI convention these types exist to
  speak. An unsigned kind reads the same byte as 255 and cannot ever answer -1.
  The twin of EnumStorageTypeKind, and it answers the same question. }
function BoolStorageTypeKind(width: Integer): TTypeKind;
begin
  case width of
    1: Result := tyInt8;
    2: Result := tyInt16;
    8: Result := tyInt64;
  else
    Result := tyInteger;
  end;
end;
