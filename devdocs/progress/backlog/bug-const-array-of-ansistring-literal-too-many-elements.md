# Bug: `const array[0..N-1] of AnsiString = (...)` literal fails "too many array constant elements" despite correct count

- **Type:** bug — Track A (compiler internals, parser / const folding)
- **Status:** backlog
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
