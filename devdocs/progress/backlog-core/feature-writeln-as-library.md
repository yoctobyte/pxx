---
slug: feature-writeln-as-library
title: "write/writeln as a library function (via `array of const` + variadic sugar)"
prio: 40
track: A
type: feature
status: backlog
owner: ""
blocked-by: [refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops]
summary: "PHASE 1 COMPLETE 2026-09-01, both slices: variadic bracket-elision -- `Log('x=', x)` against `procedure Log(const a: array of const)` -- now works for BARE ROUTINE calls (slice 1) and for METHOD calls (slice 2: instance, class, virtual, chained selector, and with fixed parameters ahead of the vector, in statement and expression position). Slice 2 also FIXED A PRE-EXISTING SILENT CRASH it uncovered: `g.D('one')`, a single elided element, compiled cleanly and segfaulted on the pinned compiler because the method loops passed a scalar where a vector was required with no diagnostic. PHASE 3 COMPLETE 2026-09-05 (65b62b148): lib/rtl/libwriteln.pas renders every type byte-identically to the builtin, asserted as PAIRS so a divergence names the type; all formatting is in Pascal and only 'emit bytes to a descriptor' stays in the compiler. Phase 3 was only worth doing once phase 1 landed -- this ticket's own 2026-07-20 note calling it 'a strictly worse writeln nobody would call' was true then and stale from 2026-09-01. THREE known holes, all in the BOXING and so unreachable from a vector reader: a QWord >= 2^63 renders signed (filed), the sized booleans render 1/0 (filed, and appended as a fourth consumer to decide-how-a-type-carries-an-identity-its-kind-cannot-hold), and a Single renders as a Double -- that last is NOT a defect, fpc has no vtSingle either, and its parity row is asserted as DIFFERENT so it goes red if one ever appears. PHASE 2 BRACKET SPELLING COMPLETE 2026-09-05: `Log(['x=', x:8:2])` parses and renders byte-identically to the builtin for float w:p, integer, Int64, QWord, Boolean, string, Char, variable width and narrow width. AND IT NEEDED NO vtFormatted TAG, which is a deliberate departure from this ticket's design -- `TextStrArg` already formats exactly these types for the write statement's variable-width path, through the same builtin formatters `Str(...)` lowers to, so a formatted element renders to an ordinary string node and boxes as a managed string. Every existing TVarRec consumer therefore reads it unchanged (sysutils.Format's FmtArg*, libwriteln, and vendored FPC code doing `case VType of`, which would have met an unknown tag 19 and fallen through its else). A new tag would have been a second copy of a formatter we already have. NOTE THE JUSTIFICATION IN THE DESIGN BELOW IS WRONG: it says `:w:p` here is 'where FPC parses width/precision too', conflating the write STATEMENT with an array-of-const literal -- measured, fpc 3.2.2 refuses `Log(['x=', x:8:2])` with `Syntax error, "]" expected but ":" found`. This is an EXTENSION, and what it earns is the gap between the builtin `writeln(x:8:2)` and a library one. PHASE 2 ELIDED SPELLING STILL NOT DONE and still blocked for the reason recorded below: it needs the shared argument loops loosened, and frankA's `refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops` is `status: working` with 25 `isNilPy` references left in `pasparser_expr.inc`, five of them in those very loops (1227, 1272, 1302, 1382, 1385) -- checked with frankA 2026-09-05 rather than assumed from the four commits whose subjects name that slug. Do NOT replace the builtin writeln: compiler.pas self-hosts on it."
---

# write/writeln as a library function (via `array of const` + variadic sugar)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-16

## Motivation

The builtin `write`/`writeln` are special-cased in codegen (`IR_WRITE` /
`IR_WRITELN`) and are not fully FPC-compatible: no file handles, partial format
support, fixed stdout. Now that `array of const` (TVarRec) is a stable,
self-hosted feature — the compiler's own asm-text emitter consumes
`items[i].VType` on all targets, element tags (incl. `vtExtended` for floats)
live in `compiler/builtin/builtinheap.pas` — `writeln` can be expressed as an
ordinary **library** routine taking `array of const`, with a little syntactic
sugar to keep the familiar call shape.

The sugar is the real win: it makes ANY user-defined variadic routine ergonomic
(`Log(...)`, `Format(...)`, `Assert(...)`), not just writeln.

**Do NOT replace the builtin writeln.** The library version must coexist and be
opt-in until it is proven byte-identical; `compiler.pas` self-hosts on the builtin
(871-proc fixedpoint) and must not regress.

## The three pieces (dependency order)

### 1. Variadic bracket-elision (useful standalone)

At a call `f(a, b, c)` where `f` resolves to a routine whose last (or only)
parameter is `array of const`, and the arguments are not already a single
`[...]` literal, auto-wrap them into the TVarRec literal: `f([a, b, c])`. The
call-arg builder already constructs `AN_VARREC_ARRAY`; do the wrap in that one
place.

- **Ambiguity rule (non-strict, predictable):** the variadic form is a
  *fallback*. Only elide brackets when no non-variadic overload matches the given
  argument list; prefer an exact non-variadic match. This avoids surprises when a
  `writeln(s: string)` overload also exists.
- **Don't double-wrap** an already-bracketed call.
- This alone lets users write `Log('x=', x, ' y=', y)` against
  `procedure Log(const a: array of const)`.

### 2. `expr:w:p` formatting via a format element

Add a `vtFormatted` element tag (in `builtinheap.pas`) carrying the value, its
underlying type, a width, and a precision. The parser — **only inside a loosened
variadic argument list** — rewrites `arg : w [ : p ]` into a `vtFormatted`
element (the `:` is unambiguous in that position; it is where FPC parses
width/precision too). The library `writeln` reads the tag and formats. Floats
already box as `vtExtended`, so `x:0:2` on a Double works.

### 3. File handles

`writeln(f, ...)` where the first argument is a file/text value routes output to
its file descriptor instead of stdout. Phase it:

- First: stdout / stderr (a `TextFile`-typed first arg resolving to fd 1/2).
- Later: real file I/O — `TextFile`, `AssignFile`/`Reset`/`Rewrite`/`CloseFile`,
  buffering. This is where the current builtin is genuinely incomplete.

## 2026-09-05 (frankH) — phase 2 bracket half landed, and the tag it specified was not needed

**What landed.** `ParseVarRecLiteralAST` now accepts `: width [ : decimals ]`
after an element expression, and formats it through `TextStrArg`. Parity against
the builtin, asserted as pairs in `test_varrec_format_bracket.pas`: float `w:p`,
float `0:p`, integer, integer width 0, Int64, QWord at the top of its range,
Boolean, string (padded), Char, a VARIABLE width, and a width narrower than the
value. `fails=0`.

**Why no `vtFormatted`.** The design above specifies a new element tag carrying
value, type, width and precision, with the library reader formatting it. That
would have been a second implementation of something that already exists:
`TextStrArg` formats exactly these types for the write statement's
variable-width path — strings padded via `StrStrW`, Boolean as `TRUE`/`FALSE`,
floats via `StrFloat` with decimals, signed and unsigned integers, Char as its
character — using the same builtin formatters `Str(...)` lowers to. Formatting
at the parse site yields a string node, so the element boxes as an ordinary
managed string.

That matters beyond tidiness. A new tag 19 would be invisible to every existing
`TVarRec` consumer: `sysutils.Format`'s `FmtArg*`, `lib/rtl/libwriteln.pas`, and
any vendored FPC code doing `case VType of`, which would fall through its `else`.
FPC has no such tag and never will. What the tag would have bought is a
consumer's ability to re-format from the raw value — no consumer does that, and
one can be added against a real caller rather than a predicted one.

**A correction to this ticket's own justification.** The design says the `:` is
where *"FPC parses width/precision too"*. That conflates two contexts. FPC parses
`x:8:2` in the **write statement**; inside an `array of const` **literal** it
refuses — measured 2026-09-05, `fpc 3.2.2 -Mdelphi` on `Log(['x=', x:8:2])`
gives `Syntax error, "]" expected but ":" found`, and pxx gave the same
diagnostic before this change. The other half of the sentence stands: the `:` is
unambiguous there, since nothing else may follow an element expression inside
the brackets. **This is an extension, and its justification is closing the gap
between the builtin `writeln(x:8:2)` and a library one**, which is what the
whole feature is for.

**frankB's condition, met.** The sign-off required that the loosening carry a
control that the parser still REJECTS what it rejected before, asserted and
branched on — and frankA added that the control must be drawn from a population
the change could actually reach. Four shapes, each a Makefile row that branches:
a stray `:` in a plain non-variadic call (`Foo(1:8, 2)`), an array index
(`a[i:2]`), a set constructor (`[1:2]`), and a third colon (`1:2:3:4`). Plus
three that must still COMPILE — a set literal, an array index, and a plain
unformatted `array of const` — because a loosening whose only evidence is that
the new syntax works cannot tell you what else it started accepting.

**A third instance of this ticket's recurring bug, found by the test's oracle.**
Writing the parity test meant rendering the same value two ways, which put
`Str(s:5, t)` beside `write(s:5)` — and `Str` on a STRING produced `4357408`,
the string's heap address rendered as digits, while `Str(c:3, t)` on a Char
produced `122`, its ordinal. `fpc 3.2.2` refuses the first (`Illegal
expression`) and ICEs on the second, so nothing depended on either answer. This
is the same defect as `bug-p-str-of-a-qword-formats-it-signed` and
`bug-p-str-of-a-boolean-formats-it-as-a-digit`: **`Str` carried a hand-written
copy of `write`'s dispatch table and was short a case every time anyone looked.**
Each previous fix added one more arm to the copy. This one deletes the copy —
`Str` now calls `TextStrArg`, which *is* write's table — so the next type added
to `write` reaches `Str` for free. The one thing `Str` does not take from
`write` is the float default: no width means FPC's scientific form, computed
before the call, which is why it is not simply `TextStrArg(expr, -1, -1)`.

**What is left.** The ELIDED spelling, `Log('x=', x:8:2)`, which needs the shared
argument loops loosened and is blocked on frankA's carve — measured, not assumed:
five `isNilPy` references remain in those loops. frankB's condition carries over
to it and frankA has said it will hold the same line if it lands there first.

## Constraints / gotchas

- **Coexistence + opt-in:** keep the builtin as default; gate the library version
  behind a unit or define. No default flip until byte-identical parity is proven
  and `make` / `make cross-bootstrap` stay green.
- **Exact output parity:** newline/flush/line-buffering, integer and float
  formatting digits. Validate against `test_conformance_*` and the cross suites.
  **The boolean fork this line used to state is not real** — it read *"PXX
  currently prints `1`, FPC `TRUE` — decide and match"*, and re-measured
  2026-09-04 `writeln(b)` prints `TRUE` on both. There is nothing to decide.
  The `1` was true of a different instrument, `Str(b, s)`, and that WAS a real
  bug — fixed the same day, see the log below. Sized booleans still print `1`
  from every renderer and are a separate filed ticket.
- **Performance:** each library `writeln` boxes a TVarRec vector (heap alloc).
  Acceptable for normal use; note it for hot logging paths; consider a fast path
  for the trivial single-scalar case if it matters.
- **Managed strings:** the library `writeln` pulls in `builtinheap` (array of
  const already allocates) — already true for array-of-const programs.

## Suggested phasing

1. Variadic bracket-elision (generic; ship + test with a user `Log`).
2. `vtFormatted` tag + parser `:w:p` rewrite in variadic arg lists.
3. Library `write`/`writeln` to stdout/stderr in a unit, behind a define; prove
   output parity on the conformance + cross suites.
4. File-handle forms (`TextFile`, Assign/Reset/Rewrite).
5. Much later: consider making the library version the default, only after a
   byte-identical self-host + cross-bootstrap proof.

## Notes

- Element tags today: vtInteger 0, vtBoolean 1, vtChar 2, vtExtended 3,
  vtPointer 5, vtAnsiString 11, vtInt64 16 (`builtin/builtinheap.pas`). Add
  vtFormatted alongside.
- Related: the bracket-elision sugar is independently valuable — could land and be
  used for user variadics well before any writeln rewrite.

## Track B note (2026-07-20)

Listed in the Track B ready queue, but phases 1 and 2 — variadic bracket-elision
and `expr:w:p` formatting — are **parser work in `compiler/**`**, i.e. Track A/P,
not Track B. Track B cannot start this; only phase 3 (the library `write` /
`writeln` over `array of const`) is ours, and on its own, called with explicit
`[...]` brackets, it is a strictly worse `writeln` that nobody would use. The
value is in the sugar, and the sugar is the compiler's.

Left in backlog rather than blocked/, since it is not externally blocked — it
just needs the owning lane to be A/P for the first two phases. Whoever ranks
this should treat it as a Track A ticket with a Track B tail.

## Lane correction (2026-07-20)

Track re-labelled B -> A on 2026-07-20: phases 1 (variadic bracket-elision) and 2 (expr:w:p formatting) are parser work in compiler/**. Phase 3, the library write/writeln over array of const, is the only Track B part and in isolation is a strictly worse writeln nobody would call — the value is in the sugar, and the sugar is the compiler's.


---

## 2026-09-01 (frankH) — phase 1 landed for bare routines, commit 7c55fb069; methods are the next slice

**Track A.** `Log('x=', x, ' y=', y)` against `procedure Log(const a: array of
const)` now compiles. Verified absent before the change (*"no overload of Log
matches these arguments: (ShortString, Integer)"*), verified present after.

### Where it went, and why that placement is the whole design

**Not in the argument loop — in the `procIdx < 0` arm beside
`TryFillTrailingDefaults`**, in `pasparser_expr.inc` (function call in an
expression) and `pasparser_stmt.inc` (procedure call statement). Two properties
follow, and the second is worth more than the first:

1. **The ticket's ambiguity rule is free.** *"Only elide when no non-variadic
   overload matches; prefer an exact non-variadic match"* IS *"run after
   `MatchCallDelphiProcAddr` has already failed"*. It is enforced by placement
   rather than by a rule that can drift.
2. **It cannot change the meaning of any program that compiles today, by
   construction** — every call it can see is one that errors without it. The
   case that would otherwise be dangerous is `array of const` PASS-THROUGH
   (`Inner(a)` from inside `Outer(const a: array of const)`), which must stay a
   forward of the same vector and must never become `Inner([a])`. **Checked by
   running it, before and after:** it resolves, so `procIdx >= 0` and the
   elision is never reached. There is a row for it in the test that fails if
   the placement ever moves.

Slots are tried **largest-first** (most fixed parameters bound is the most
specific reading); each candidate is committed, re-resolved through the real
resolver, and rolled back on refusal. **Nothing in the new code decides whether
a call matches** — `MatchCallDelphiProcAddr` does, on a chain rewritten into a
shape it already understood. So a candidate scan that is too loose costs a
rejected retry, never a wrong bind.

### `MakeVarRecArrayFromArgs` — extracted, not duplicated

frankA's catch, and it was the real risk. There is exactly ONE place in the
compiler that constructs an `AN_VARREC_ARRAY`: `ParseVarRecLiteralAST`. But it
is a *parser* — `Expect(tkLBrack)`, loop, `Expect(tkRBrack)` — and at the
elision hook the arguments are already an AN_ARG chain with no brackets left to
consume, so it cannot be called. Hand-building the node there would have made
this the second construction site, which is what
`normalise-dont-special-case.md` is actually about.

So the four lines that decide what the node IS were pulled out into
`MakeVarRecArrayFromArgs(elemHead)` and both callers use it. They now differ
only in how they obtained the element chain.

### Gate, and both controls were RUN

`make compiler/pascal26` — **`converged after 1 round(s)`**, the recompute verb,
not the stamp. `tools/gate.sh quick` **GREEN**, with the FPC seed canary
**PASS** rather than SKIP (the tree still had uncommitted `compiler/**`, which
is the only condition under which that canary runs at all).

`test/test_variadic_bracket_elision.pas`, 14 rows, registered in `test-core`.
**The load-bearing rows are the `same-as-brackets` pairs** — they compare the
elided call against the explicitly bracketed call of the same routine, which is
what pins the two spellings to one builder. Everything else could be satisfied
by an elision that builds a subtly wrong node and still prints something.

| control | result |
| --- | --- |
| hook disabled (`procIdx := -1`) | the test file **does not compile**; recipe exits 1 |
| node hand-built without `TVarRecId` | **compiles cleanly**, prints `?` element tags, 6 rows RED |

The second is the one that matters: it is exactly the failure frankA predicted,
it produces no diagnostic at all, and it would have been invisible to every
test that existed before this one.

### The boundary — stated because it is not obvious from the feature's name

**Method calls are NOT covered.** `g.Log('a', 1, 2)` is still
`wrong number of parameters in call to TLogger.Log`. The method paths parse
arguments **driven by the signature**, slot by slot, and `ExpectCallRParen`
fires on the leftover tokens — so they never reach `MatchCallDelphiProcAddr`
and never reach this hook. Covering them means keeping parsing at the last slot
when that slot is `array of const`, across the ~6 method argument loops that
share `ExpectCallRParen`. That is a different mechanism in a different file and
it is the next slice, not an oversight.

**The NilPy sites are deliberately out of scope.** `MatchCallDelphiProcAddr`
has four call sites, not two: `pyparser.inc:49079` and `:49097` are the other
pair. Python has its own `*args` packing (`PyPackStarArgs`) and this is a
Pascal-surface feature, so they were left alone **on purpose** — recorded here
because the next person to touch elision will find four sites with two handled.

Phases 2 and 3 are untouched.


---

## 2026-09-01 (frankH) — slice 2: method calls, and the crash that was hiding behind them

`g.Log('x=', x)` now compiles, for every method shape. The boundary the phase-1
note stated — *"method calls are NOT covered … that is the next slice"* — is
closed.

### It is a different mechanism, not a missing call to the phase-1 one

Phase 1 hooks the `procIdx < 0` arm: it runs after `MatchCallDelphiProcAddr`
has FAILED, and re-resolves. The method paths never reach that resolver — `mpi`
is bound by name on the class and the arguments are then parsed **slot by slot,
driven by the signature**. Nothing failed and there is nothing to re-resolve;
the call simply runs out of declared slots with tokens left over.

So the absorb happens where the surplus still exists, in `ExpectCallRParen` —
**the shared tail all seven loops already funnel through.** Its own comment says
it exists precisely so there is not a seventh hand-written guard, so that is
where a seventh special case would have gone wrong. `ExpectCallRParen(mpi)`
became `ExpectCallRParen(mpi, lastArg)`; one implementation, seven mechanical
call sites, one place that decides.

### The pre-existing crash

Building the test found something the ticket did not predict. **`g.D('only')` —
one elided element — compiled cleanly and SEGFAULTED at run time.** The method
loops did not know `array of const` at all, so a scalar was passed where a
vector was required, with no diagnostic. **Verified on the PINNED compiler**, so
it is pre-existing and not a regression from this work.

It is fixed here rather than filed separately because the bare-routine spelling
of the identical source, `Desc('only')`, already produced a correct one-element
vector via phase 1. Leaving it would have shipped a compiler where
`g.D('a', 1)` works and `g.D('a')` crashes — the two-spellings-one-concept split
`normalise-dont-special-case.md` exists to refuse. **It is also why the absorb
cannot be gated on seeing a surplus:** that call has no comma, and the first cut
of this slice gated on `tkComma` and silently left it crashing.

### The guard phase 1 got for free, and this one had to state

`array of const` **pass-through** — `Inner(a)` from inside
`Outer(const a: array of const)` — must forward the same vector and must never
become `Inner([a])`. Phase 1 was immune by construction (such a call resolves,
so its hook was never reached). With no resolution step to lean on, the guard is
explicit and is a type test: skip when the argument is already record-typed,
which `ParamIsVarRecArrayAt`'s own comment licenses — in this dialect an open
array of record is only ever `array of const`. **Measured before it was
written**, via `PXXDBG=a.ast`: a forwarded argument is `AN_IDENT` with
`tk = tyRecord`; an elided element never is.

### Deliberately NOT gated on `isNilPy`

The obvious way to honour phase 1's "NilPy sites are out of scope" note would be
`if isNilPy then Exit`. That would be wrong for the reason `defs.inc:3955`
already documents: **`isNilPy` is true for the WHOLE compilation**, including
the nested `uses` of every Pascal RTL unit a NilPy program drags in — so it
would disable this for ordinary Pascal library code merely because the program
at the root was Python. The real gate is structural and language-independent.
The one NilPy-specific site (`pasparser_expr.inc`, the keyword-argument path)
passes `-1` instead, because `PyBindKwArgs` has just reordered that chain and
its `mlastArg` is no longer the tail.

### Tests and the controls, which were RUN

`test/test_variadic_elision_methods.pas`, 18 rows in `test-core`. The rows
enumerate the loops rather than the feature — statement vs expression position,
instance / class / virtual / chained selector, fixed parameters ahead of the
vector — because a fix reaching one loop would pass a one-shape test. The
load-bearing rows are again the `same-as-brackets` pairs.

| control | result |
| --- | --- |
| absorb disabled | test file **does not compile** — `wrong number of parameters in call to TLogger.D` |
| pass-through guard removed | both `passthrough` rows **RED**, forwarded vector wrapped into a vector-of-one-vector |

`test/test_variadic_elision_method_refusal.pas` is the wrap-a-wrap positive
control: `g.D(['already', 1], 2)` must stay an arity error, and the recipe greps
for the diagnostic rather than just asserting non-zero exit.

**Gate:** `make compiler/pascal26` **`converged after 1 round(s)`** (the
recompute verb), binary `ea4a720bf6f9`; `tools/gate.sh quick` **GREEN**, with
the FPC seed canary **PASS rather than SKIP** — which matters here because this
adds a forward declaration to `compiler.pas`, and declaration order is exactly
the class only that canary catches.

### Still open

Phases 2 and 3, untouched. Also unchanged: the two `pyparser.inc` resolver
sites, still deliberately out of scope.

---

## 2026-09-04 (frankH) — phase 3 scoped, phase 2 deliberately not taken, and one bug found scoping it

Reached from the age-ordered queue as the second-oldest open ticket.

### Phase 2 is in another agent's active region, and should not be first anyway

`expr:w:p` splits by spelling. In the BRACKET form it is contained:
`ParseVarRecLiteralAST` (`pasparser_lval.inc:3421`) parses each element with a
bare `ParseExpr`, and the `:w:p` parse goes there. In the ELIDED form it is not
contained at all — the elements are parsed by the ordinary call-argument loops
**before** either elision hook is reached, so `ParseExpr` stops at the `:`, the
arg loop wants `,` or `)`, and `Log('x=', x:8:2)` never reaches phase 1's
`procIdx < 0` hook or `AbsorbVariadicTailArgs`. Covering it means loosening the
shared argument loops, which is exactly where frankA is carving NilPy arms
(`refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops`).
Checked with them; **phase 2 stays unclaimed by both of us** until that lands.

Independently, phase 2 first would bank a half: `vtFormatted` with no reader is
a tag with no consumer, and phase 3 is its reader.

### Phase 3 is no longer "worthless in isolation" — phase 1 is what changed that

The Track B note above (2026-07-20) parks phase 3 as *"in isolation a strictly
worse writeln nobody would call — the value is in the sugar, and the sugar is
the compiler's."* **That was correct when written and is now stale.** The sugar
landed 2026-09-01, both slices, so `LogLn('x=', x)` already compiles against
`array of const`. Phase 3 is also pure `lib/rtl` — Track B, `$(PXX_STABLE)`, no
`compiler/**` — so it collides with nobody, and `sysutils.Format` already
dispatches on `VType` through `FmtArgInt/FmtArgStr/FmtArgFloat/FmtArgIs32`,
which is the machinery a library `writeln` needs.

### The parity target, measured rather than assumed

What the builtin `writeln` actually prints, `c94252bb92cd`, all matching
`fpc 3.2.2 -Mdelphi -O1`:

| type | rendering |
| --- | --- |
| Integer / Int64 / QWord | plain digits, `-42`, full unsigned range |
| Boolean | `TRUE` / `FALSE` |
| Char / ShortString / AnsiString | the value |
| Double | ` 3.5000000000000000E+000` (leading space, 16 digits, `E+000`) |

`Str(d, s)` reproduces the float form exactly, so library code has a reachable
route to it and does not need its own float formatter.

### The bug this scoping found

Building that table put `Str` and `writeln` side by side on the same value, and
they disagreed: `Str(b, s)` printed `1` where `writeln(b)` printed `TRUE`.
Filed and fixed as [[bug-p-str-of-a-boolean-formats-it-as-a-digit]] — one
missing dispatch arm, `StrBool` already existed and was correct. The sized
booleans lose the same information in all three renderers (`Str`, `writeln`,
and `array of const` boxing, where `LongBool` boxes `vtInteger` rather than
`vtBoolean`) for a different reason, and are
[[bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln]].

**That second one lands on phase 3 directly:** a library `writeln` reads
`VType`, so it will render a `LongBool` as a number no matter how carefully it
is written. Whoever takes phase 3 should treat it as a known hole rather than
re-derive it from a failing parity row.

Phases 2 and 3 remain untouched. Phase 3 is scoped, not started.

---

## 2026-09-05 (frankH) — phase 3 landed: `lib/rtl/libwriteln.pas`

`65b62b148`. Track B, no `compiler/**` touched. What the unit is and why it is
shaped that way is in its own header; what belongs here is the three decisions
a later reader would otherwise re-litigate.

**1. The byte sink is still the builtin, and that is the design.** Each routine
assembles one `AnsiString` and hands it to `write(s)` / `write(StdErr, s)`. All
the FORMATTING — the part that is incomplete and hard to change in codegen —
moves into Pascal; the only thing left in the compiler is emitting bytes to a
descriptor. That is also what makes the unit portable to every backend including
ESP, since it needs no syscall of its own. Phase 4 (file handles) extends the
sink; it does not need to revisit the formatting.

**2. Parity is asserted as PAIRS, not as a golden file alone.** Every type is
printed once through each renderer, so a divergence names the TYPE rather than
saying "output differs". The `.expected` stops the two drifting together and the
fpc oracle says the bytes are right rather than merely agreed.

**The `double` row is the one that discriminates and it was chosen that way.** A
library renderer reaching for the obvious tool, `sysutils.FloatToStr`, prints
`3.5` where the builtin prints ` 3.5000000000000000E+000` — and **every other
row still passes with that mistake in place.** Proved by putting `FloatToStr`
back and watching the row go red, rather than by arguing it.

**3. One pair is asserted as DIFFERENT on purpose**, which is rarer than it
looks and is why it is written down. A `Single` boxes as `vtExtended`; there is
no `vtSingle` in this compiler or in fpc, measured both ways, so the width is
gone before any vector reader sees it. Not a defect — fpc's `writeln(Single)`
and `writeln(Double)` match ours exactly, and an fpc library writeln would lose
the same width for the same reason. The row exists so that if a `vtSingle` ever
appears it goes RED and tells whoever added it that the library can now do
better. An omitted row would have said nothing.

### The two holes that ARE ours, kept apart on purpose

They look like one finding and they are not:

- **`QWord` boxes as `vtInt64`** where fpc emits `vtQWord`. `vtQWord` is
  declared here and emitted by nothing — an identity that HAS a carrier which
  nothing writes to.
- **The sized booleans box as `vtInteger`** — an identity with NO carrier at
  all, which is why it went to
  [[decide-how-a-type-carries-an-identity-its-kind-cannot-hold]] as a fourth
  consumer rather than being filed as a bug with a fix.

They were found in one program and that is their only relationship. Bundling
them would send whoever takes the first one looking for a fork that does not
apply to it.



## 2026-09-05 (frankH) — the block was in the prose only, and the count is unchanged

Phases 1, 2-bracket and 3 are landed; the ONLY item left is the phase-2 ELIDED
spelling, and that has been blocked on frankA's
[[refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops]]
since 2026-09-05 — recorded in the summary and **not in the frontmatter**, so
`ready --track A` offered the whole ticket as available work while its own
summary said the remaining half could not be started. Edge added.

Re-measured rather than re-asserted, twice today at different tips:
`grep -c isNilPy compiler/pasparser_expr.inc` is **25**, and the five in the
shared argument loops are still at 1227, 1272, 1302, 1382, 1385. The carve is
`status: working`, `owner: frankA`. Nothing has moved.
