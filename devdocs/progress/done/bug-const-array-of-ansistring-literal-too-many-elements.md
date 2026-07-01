# Bug: `const array[0..N-1] of AnsiString = (...)` literal fails "too many array constant elements" despite correct count

- **Type:** bug — Track A (compiler internals, parser / const folding)
- **Status:** done
- **Opened:** 2026-07-01
- **Found by:** building the `-S` x86-64 disassembler (feature-asm-textual-emit-mode
  task #7) — several lookup tables (`array[0..15] of AnsiString` register
  names, `array[0..7] of AnsiString` mnemonic names) compiled fine under FPC
  but failed self-host (`pascal26` compiling `compiler.pas`) with `error: too
  many array constant elements ()`, even though the initializer's element
  count matched the declared array bounds exactly (hand-counted multiple
  times; also tried both function-local and unit-level placement — neither
  avoided the error). `grep -rn "array\[0\.\..*\] of AnsiString = ("` across
  the entire existing codebase (`compiler/*.pas`, `compiler/*.inc`) returns
  **zero** other hits — nothing in this self-hosting compiler had ever used
  this construct before, so this is untested territory rather than a
  regression or a usage mistake.

## Repro

Not yet minimally isolated in this session (time-boxed in favor of the
workaround, see below) — the working assumption based on what changed
between "fails" and "compiles" is a `const <name>: array[0..N-1] of
AnsiString = ('a', 'b', ..., N literals);` declaration, N in the 8-16 range,
tried both as a unit-level const block and as a function-local const block.
A future pickup should start by re-deriving a minimal repro (the git history
around this ticket's opening commit has the original failing declarations
in `compiler/asmdisasm_x64.inc`, since reverted to a `case`-statement
workaround, as reference material).

## Suspected shape

`ParseTypeSection`/`ParseVarSection`'s array-constant-initializer parser
(`compiler/parser.inc`, the `cElem >= cFlatLen` check, ~line 9789) computes
`cFlatLen` from the array's declared bounds via `AllocArray`. Given the
initializer counts were hand-verified correct multiple times, the likely
culprit is `cFlatLen`/`cLo`/`cHi` being computed *wrong* for an
`AnsiString`-element array specifically (a stride/size miscalculation
unique to managed types, matching the general "array + AnsiString" fragility
theme already surfacing this session — see the sibling
`bug-var-array-of-ansistring-param-loses-writes` ticket, though that one is
about `var` *parameters*, a different code path, not const declarations).

## Impact

Hard parse error (loud, not silent) — but a confusing one, since the error
message ("too many array constant elements") strongly implies a *user*
counting mistake, sending anyone who hits this down the wrong debugging path
first (this session spent real time re-counting correct initializers before
suspecting the compiler itself).

## Workaround used

Replaced every `const array[..] of AnsiString = (...)` literal in
`compiler/asmdisasm_x64.inc` with a plain `function Foo(idx: Integer):
AnsiString; begin case idx of 0: Result := '...'; ... end; end;` lookup —
proven-safe, used pervasively elsewhere in this codebase already. Slightly
more verbose but functionally identical and avoids the parser gap entirely.

## Suggested fix

Needs a minimal isolated repro first (see above), then a trace through
`AllocArray`'s bounds computation and the const-array-initializer parsing
loop (`compiler/parser.inc` ~9760-9800) specifically for `tyAnsiString`
element type, comparing against the same logic for a scalar element type
(e.g. `Integer`) which presumably works (no existing failures reported for
`const array[..] of Integer = (...)`, a much more common pattern in this
codebase).

## Also worth checking while in there

- Does the bug reproduce for *any* AnsiString array size, or only above/
  below some threshold? (Unconfirmed — both a 16-element and an 8-element
  array failed in this session, so probably not a small-N-only issue, but
  not exhaustively tested.)
- Local (function-scoped) vs. unit-level (global) const placement: both were
  tried during this session and both failed identically, ruling out scope as
  the variable — worth noting in whatever eventually fixes this, so a future
  reader doesn't re-waste time on that hypothesis.

## Fixed (2026-07-01, Track A)

Root cause (found via a dispatched research agent, verified by direct code
reading): `compiler/parser.inc`'s array-const element loop (~9781-9812)
consumed each element via `ParseInitVal` -> `ConstEval` -> `ConstEvalFactor`.
`ConstEvalFactor` has exactly ONE branch that matches a `tkString` token — a
*single-character* literal, treated as an ordinal (`Ord(CurTok.SVal[1])`,
for `Char`-constant contexts) — and calls `Next` to consume it. A
multi-character string literal matches NO branch in `ConstEvalFactor`;
execution falls through to `Result := 0` WITHOUT calling `Next`, leaving the
token stream un-advanced. The outer loop's `Inc(cElem)` runs unconditionally
regardless of whether a token was actually consumed, so it re-examines the
same un-consumed string token on the next iteration, incrementing `cElem`
again with zero real progress — `cElem` reaches `cFlatLen` (the correct
element count) long before the real token stream reaches the closing `)`,
firing the misleading "too many array constant elements" error on a
perfectly correctly-counted initializer. The *single*-char case (e.g.
`array[0..15] of AnsiString = ('a','b',...)`) doesn't hit the parse error at
all — `ConstEvalFactor` matches it, `cElem`/token-stream stay in lockstep —
but silently stores `Ord(char)` as a plain `AN_INT_LIT` where a managed-
string handle is expected, segfaulting at runtime instead. Confirmed: this
is a genuine unimplemented-feature gap, not a miscount — a doc comment right
above the array-const path already said so ("string/float/record
initializers remain a follow-up"), and `PendingInitKind`/`LocalInit*` had no
string-literal wiring for array elements (a separate `Kind=1` string-literal
mechanism already existed and is used by the C frontend for globals, just
never wired up from the Pascal array-const parser).

**Fix**: when the array's element type is a string kind
(`tyString`/`tyAnsiString`/`tyFixedString`/`tyShortString`), the element loop
now bypasses `ParseInitVal`/`ConstEval` entirely and captures the literal's
span directly (`Tokens[TokPos-1].SOffset`/`SLen`, the same pattern the
existing scalar typed-string-const path already uses), recording it as a
`Kind=1` (string literal) init instead of a plain int. For GLOBAL consts this
reuses the pre-existing `PendingInitKind=1` mechanism (already consumed
correctly by `CompilePendingGlobalInits`, building an `AN_STR_LIT` node —
zero changes needed there). For LOCAL (routine-scoped) typed consts, added a
matching `LocalInitKind` array (`compiler/defs.inc`, mirroring
`PendingInitKind`) plus a new `AN_STR_LIT` branch in
`CompilePendingLocalInits`, since that path had no string-literal support at
all before this fix. Both emit a normal `arr[elem] := AN_STR_LIT` assignment
— the exact same managed-string coercion/allocation any ordinary `s :=
'literal'` already gets, so no new ARC logic was needed.

**Verified**: multi-char and single-char elements, global AND local typed
array consts, plus a reassignment-after-init check (`Multi[1] := 'zzz'`
after reading the original value into a separate var) proving the element is
a real independently-refcounted managed string, not an aliased literal.
Matches FPC output exactly (`fpc` build of the same source). New
`test/test_const_array_of_string.pas` in `make test-core`. Full `make test`
green, self-host bootstrap byte-identical (pinned v115).

## Log
- 2026-07-01 — resolved, commit HEAD.
