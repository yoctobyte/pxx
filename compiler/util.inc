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

function TargetIsEspClass: Boolean;
{ True for the ESP-class bare-metal targets — the ones that have no hosted OS
  under them and therefore no full RTL: xtensa ALWAYS, riscv32 only under
  `--esp-profile=bare`. riscv32 is dual-role (bare ESP32-C3 or hosted Linux),
  which is exactly why the profile has to be part of the test and why writing it
  out by hand is a trap.

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
  Result := (TargetArch = TARGET_XTENSA) or
            ((TargetArch = TARGET_RISCV32) and EspBareBoot);
end;
