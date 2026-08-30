---
slug: bug-c-an-unterminated-declaration-still-parses-the-appended-pascal-rtl
track: C
prio: 50
type: bug
blocked-by: []
summary: "The statement half of bug-c-an-unterminated-construct-parses-past-eof is fixed; the DECLARATION half is not. An unterminated `struct`/`enum`/initializer still swallows the appended Pascal RTL and fails with `main function not found` at line 1313 of platform_backend.pas."
status: backlog
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
