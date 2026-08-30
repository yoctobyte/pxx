---
slug: bug-c-an-unterminated-declaration-still-parses-the-appended-pascal-rtl
track: C
prio: 50
type: bug
blocked-by: []
summary: "The statement half of bug-c-an-unterminated-construct-parses-past-eof is fixed; the DECLARATION half is not. An unterminated `struct`/`enum`/initializer still swallows the appended Pascal RTL and fails with `main function not found` at line 1313 of platform_backend.pas."
status: done
owner: frankC
---

# An unterminated C declaration still parses the appended Pascal RTL

Split from `bug-c-an-unterminated-construct-parses-past-eof-into-the-appended-pascal-builtins`,
whose statement half landed. Three shapes are still wrong, measured at the fix's
own build:

```
struct S { int a;          -> pascal26:1313: error: main function not found
enum E { A, B                    in: ./compiler/../lib/rtl/platform/posix/platform_backend.pas
int a[] = { 1, 2                 near: pid  end  end  >>>
```

Same cause as the statement half: the C stream's `tkEOF` is deleted when units
are appended, so a `while CurTok.Kind <> tkEOF` in a member list cannot fire
until the Pascal RTL has been consumed as C members.

## Why the statement fix does not cover it

The fix normalised fourteen `while (CurTok.Kind <> tkEnd) and (CurTok.Kind <>
tkEOF)` loops onto one `CBlockContinues`, which refuses when the cursor reaches
Pascal. The declaration side is a **second loop family** — fifteen `while
CurTok.Kind <> tkEOF do` with an internal break — and it cannot be converted
blindly, because **two of the fifteen are the top-level passes**
(`ParseCUnitPass` 13089, `ParseCUnit` 13121) which *deliberately* walk the
appended region: `else if ... (TokPos - 1) >= userTokEnd then Next` exists to
skip already-compiled pulled-unit tokens. Refusing there would fail every C
compile.

So the members of that family split into "must stop" (`CInitWalkRecord`,
`CInitWalkArray`, `CInitSkipScalar`, `CDeferScalarPtrInitSkip`,
`SkipCDeclToSemi`, the `ParseCSizeof` walks) and "must continue" (the two
top-level passes), and telling them apart is the work.

## The root cause under both halves, and the design question

**The C parser has no end.** `CLexAppend` deletes the C `tkEOF` (`Dec(TokCount)`
when `MainProgramTokCount = TOK_UNBOUNDED`) so the pulled crtl prototypes can be
walked as one stream — deliberate, and it is what makes the pull work. The price
is that every `tkEOF` test in the C parser is a test that cannot fire, and each
loop family has had to grow its own substitute.

The alternative worth costing before adding a third guard: give the C parser a
real terminator. `userTokEnd` already exists and is already consulted at one
top-level site. A single "the C region ends here" the parser can see would make
`tkEOF` mean what it says in all thirty loops and delete both guards. That is
one mechanism instead of three, which is the call
`devdocs/dev/normalise-dont-special-case.md` asks for — and the reason to file
it rather than bolt on the second guard now.

## Gate

`struct S { int a;`, `enum E { A, B` and `int a[] = { 1, 2` each report an
unterminated-construct error on their own C line, with no `in:` line and no
Pascal in the `near:` window. `cunterm` / `cunterm_pull` stay green, and so do
the C corpus tests (an appended crtl region must still be walked). Self-host
byte-identical.

## Re-priced 40 -> 50, 2026-08-30 (coordinator, on frankC's costing)

Filed at 40 as a default, not as a judgement. frankC costed it after landing
`bug-c-an-unterminated-construct-parses-past-eof` and the number is 50:

- it deletes **two** guards (`CBlockContinues` and the `ParseCStatementAST`
  entry) instead of adding a third, and makes `tkEOF` mean what it says in all
  ~30 loops — a class closed rather than a symptom;
- half a day if the sentinel goes in cleanly, a full day with the index-shift
  verification;
- **entirely inside `clexer.inc` / `cparser.inc`** — no shared files, no grant;
- and it is the top takeable item in Track C's ready list, so leaving it at a
  default 40 mis-ranked the lane's own head.

Not higher: nothing is blocked on it, and the remaining symptom is typo-shaped —
an unterminated `struct` is not a thing that reaches a corpus.

**The risk to plan around is not the sentinel, it is the index shift.** A planted
token moves every token index, and three tables are index-keyed: `CModRange*`,
`PasSrcRange*`, `DbgRange*`. `AdjustSrcRanges` exists for exactly this, so the
machinery is there — but it is three tables plus a `tkEOF` that other frontends'
code also tests.

**And the part a blind conversion breaks:** two of the fifteen top-level passes
*deliberately* walk the appended region and must be taught to step over the
sentinel. Converting them along with the rest fails every C compile.

**Superseded in its costing, not in its ranking — see the next section.** That
estimate was mine and it was too big: the sentinel does not need planting,
because it already exists and is being deleted. No index shift, no
`AdjustSrcRanges`, no three tables. The 50 stands; the day-of-work does not.

## ROOT CAUSE FOUND — one line, one branch, and NilPy already does it right. frankC, 2026-08-30

Measured, not reasoned. The chain is complete and it is shorter than the
"terminator" design this ticket originally costed.

**1. Every appender deletes a trailing `tkEOF`, and both guard it the same way.**
`CLexAppend` (`clexer.inc:874`) and its Pascal twin (`lexer.inc:2723`) both open:

```pascal
if (MainProgramTokCount = TOK_UNBOUNDED) and (TokCount > 0)
   and (Tokens[TokCount-1].Kind = tkEOF) then Dec(TokCount);
```

So the deletion is **conditional on `MainProgramTokCount` never having been
set**. `TOK_UNBOUNDED` is `High(Integer)` and `compiler.pas:1829` sets it once,
commented *"= not set yet; the frontends overwrite it"*.

**2. The C branch does not overwrite it.** `compiler.pas:1923`:

```pascal
CLexAll;
DbgMainTokEnd := TokCount;   { -g: see the NilPy branch above }
TokPos := 0;
```

**3. The NilPy branch, thirty lines above, sets BOTH:**

```pascal
PyLexAll(False);
DbgMainTokEnd := TokCount;
MainProgramTokCount := TokCount;
```

with a comment about why the *first* one matters. Nothing says why the second
does, and the C branch copied the line that was explained.

### So the fix is one line

`MainProgramTokCount := TokCount;` after `CLexAll`. Both appenders then stop
deleting the C `tkEOF`, the C stream gets a real end, and **all three loop
families work unchanged** — the `while ... tkEOF` in `ParseCUnitPass`, the
`while (tkEnd) and (tkEOF)` that is now `CBlockContinues`, and the
scan-to-semicolon in `ParseCStructDecl:13077`. Both guards added by
`bug-c-an-unterminated-construct-parses-past-eof` become dead and delete, and so
does the `(TokPos - 1) >= userTokEnd` arm at `cparser.inc:9939`, which exists
only because the pass ran into the appended region.

**It is one line in `compiler.pas`, which is Track A ground** — Track C files
this rather than editing it. The C-side dead-code removal is Track C's and
follows.

### What to verify, because a one-line fix here is not a small change

- The crtl pull already repositions by index (`crtlStart := CPullCrtlForPrototypes;
  TokPos := crtlStart; Next;`), so pass 1 stopping at the user EOF is what that
  code already expects. **Pass 2 and the RTL/`pxxcio` appends must be checked the
  same way** — if either relies on walking *through* the boundary, it needs the
  same explicit reposition.
- `MainProgramTokCount` is read by `bparser`, `pyparser` and `rparser`, never by
  the C path, so setting it cannot change another frontend's behaviour — but it
  is a global, so confirm rather than assume.
- The three C corpora (zlib, lua, quickjs) are the population that would notice a
  boundary landing one token early.

### Why the earlier "give it a terminator" estimate was too big

That design planted a sentinel and shifted every token index, which would have
touched `CModRange*`, `PasSrcRange*` and `DbgRange*` through `AdjustSrcRanges`.
None of that is needed: **the sentinel already exists and is being deleted.**
The work is to stop deleting it, then remove what grew around its absence.

## Fixed at the root: the C region now HAS an end. frankC, 2026-08-30

**One line, and it is not in `compiler.pas`.** `CLexAll` (`clexer.inc`, Track C's
own file, one caller) now ends with `MainProgramTokCount := TokCount;`. Both
appenders delete a trailing `tkEOF` only while that global is still
`TOK_UNBOUNDED`, so saying where the C program ends is what keeps its EOF alive.
The `compiler.pas` grant (`grant-compiler-pas-c-branch-tok-unbounded-to-frankc`)
was **not needed and not used** — the lexer is a better place for it than the
driver anyway, because the lexer is what knows it has finished the main source.

| shape | `pinned` 53800fbeb0b6 | now |
| --- | --- | --- |
| `struct S { int a;` | `1313: main function not found` (platform_backend.pas) | `1: unterminated C construct` |
| `enum E { A, B` | same | `1: unterminated C construct` |
| `int main(void) { return 1;` | `2: expected C expression` + `in: builtinheap.pas` | `1: unterminated C construct` |
| a C program with **no main at all** | `1313: main function not found` + a `near:` of Pascal RTL | `1: main function not found` |

**No C diagnostic quotes Pascal any more**, which is the property the tests
assert directly (`grep -qi 'builtinheap\|platform_backend\|\.pas'` must NOT
match).

### Both guards deleted, as predicted

`CTokIsPastCSource` is **gone** — the boundary is a real token again, so a
source-range lookup is not needed to find it. `ParseCStatementAST`'s entry guard
is gone; its plain `if CurTok.Kind = tkEOF then Exit` works again because the
enclosing loop now refuses. What remains is one line in `CBlockContinues`:

> **A braced list that reaches end of file is UNTERMINATED, always.** No C
> construct is well-formed with an open brace and no closing one, so `tkEOF`
> there is not "stop", it is "refuse". Returning False handed the raw
> `Expect(tkEnd)` a token it cannot name — `Expected: ..., but got:  (Kind: 0)`,
> which is what one intermediate build printed.

Same one-line refusal added to `SkipBraceBlock` (depth still open at EOF) and to
the missing-main error, which ran *after* both passes with the cursor past every
appended unit and so read its `in:`/`near:` context from the RTL.

### An off-by-one the fix itself created, and caught

With a real `tkEOF` the cursor sits **on** it, and its `Line` is one past the
last line of the file — so every unterminated-construct error moved from line 1
to line 2. `CLastCSourceLine` now walks back over `tkEOF` tokens. That number is
a parsed interface (the IDE keys jump-to-error off it), so one out is not
cosmetic. Caught because the two `cunterm` rows assert the exact line.

### Two residual defects, and neither is this one

Filed separately rather than stretched into this ticket:

1. **`struct S { int a;` followed by `int main(void) { ... }`** is *not*
   unterminated: `main`'s closing brace closes the STRUCT, and `main` is
   swallowed as a member. gcc: `expected ':', ',', ';', '}' or '__attribute__'
   before '{' token`. A member declarator followed by a brace should be an
   error. → [[bug-c-a-function-definition-after-an-unclosed-struct-is-eaten-as-a-member]]
2. **`int a[] = { 1, 2` alone** reports `main function not found` (true — there
   is no main) rather than naming the unclosed initializer. The initializer
   walkers do stop at EOF; they just do not complain.
   → [[bug-c-an-unclosed-initializer-list-reports-the-next-error-instead-of-itself]]

### Gate

Self-host converged, 1 round, `231433050493`. forwardlint clean of C-lane
failures. 12 C corpus programs compile. Five `test-core` rows, **all five real
before/afters** against `pinned`: `cunterm`, `cunterm_pull`, `cunterm_struct`,
`cunterm_enum`, `cnomain`.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
