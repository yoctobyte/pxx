---
summary: "DONE 2026-09-04, both halves. Gating: {$ASSERTIONS ON/OFF}, {$C±}, -Sa, --no-assertions — the condition is no longer evaluated when off, and --no-assertions reproduces fpc 3.2.2's column exactly. Message: `boom (file.pas, line 28).` byte-identical to FPC across four shapes including an Assert inside an include, where FPC names the INCLUDE's file and line. The ticket's sketch of the message was wrong and is corrected in the body: the message REPLACES `Assertion failed` rather than following it"
type: feature
track: P
prio: 30
status: done
owner: 
---

# `{$ASSERTIONS}` gating and the `(file, line N)` message suffix

- **Type:** feature — FPC parity. Track P (directive + call lowering), touching
  Track A's `compiler/builtin/builtin.pas` for the message.
- **Opened:** 2026-08-06, from [[decide-assertions-directive-and-message-format]]
  (decided: **both**).

## Two independent halves

### 1. Gating — the behavioural one

FPC compiles `Assert` **out** unless `-Sa` or `{$ASSERTIONS ON}`. pxx always
evaluates it. That is not only a cost difference: an assertion whose condition
has **side effects** runs in pxx and does not in FPC, so the two dialects can
take different paths. Prefer landing this half first if the two are separated —
it is the one that changes behaviour.

Needs: a `{$ASSERTIONS ON/OFF}` directive alongside the existing switch family
in `lexer.inc`, a `-Sa` command-line flag, and suppression of the whole call at
lowering (not merely a runtime no-op — the point is that the condition is not
evaluated).

Default: **on**, keeping today's behaviour for existing code. FPC's default is
off, but flipping it silently would turn every existing pxx assertion into dead
code, which is the worse failure. Worth a line in the docs either way.

### 2. Message format — the cosmetic one

FPC appends the position:

    Assertion failed (file.pas, line 12)

pxx omits it. Needs the source position threaded into `__pxxAssert`
(`compiler/builtin/builtin.pas`), which already takes the message and already
routes through `AssertErrorProc` when `sysutils` is used
([[compat-pascal-assert-halts-instead-of-raising-eassertionfailed]], done).

## Note

`AssertErrorProc` is already in place and already receives the message, so the
position argument should reach both the hook and the default print path —
otherwise `sysutils`' `EAssertionFailed` would carry a less useful message than
the bare printer, which is backwards.

## Gate

`{$ASSERTIONS OFF}` leaves no trace of the condition (verify a side-effecting
condition does **not** run, not merely that nothing prints); `-Sa` matches;
the default is unchanged for existing sources; the failure message matches
FPC's text including position; `test_assert_raises_with_sysutils` still passes.

## Triage 2026-08-19 (Track D re-triage pass, pin v363) — RE-TYPED feature -> bug

```pascal
function Bump: Boolean; begin n := n + 1; Bump := True; end;
...
n := 0;
{$ASSERTIONS OFF}
Assert(Bump, 'never');
WriteLn('n=', n);        { pxx v363: n=1   FPC: n=0 }
```

The directive is **accepted and silently ignored** — it does not even warn.
That is this repo's named promotion case: an ignored directive that changes the
values a program computes is a bug, not a parity nicety. Half 1 (gating) is
therefore the bug; half 2 (the `(file, line N)` suffix) remains cosmetic and is
still just parity work.

Also measured, for whoever takes half 2: pxx's failure message today is
`Assertion failed: boom` with exit status 227 — so the suffix is missing, and
the whole line shape differs from FPC's, not only the position.

Everything else in the ticket stands, including the deliberate choice to keep
the default **on**.

## Half 1 (gating) landed 2026-09-04 (frankS, Track P). Half 2 still open.

The ticket's own advice taken: the two halves separated, the behavioural one
first.

**What landed.** `{$ASSERTIONS ON/OFF}`, `{$C+}`/`{$C-}` (the TP/Delphi letter
spelling, which the ticket did not mention and which is a second path to one
state — the sibling this repo's `normalise-dont-special-case` rule is about),
`--no-assertions`, and `-Sa`. Lexically scoped through a new `TokAssertions`
token-parallel array beside `TokQChecks`, so a region of a file can differ from
the rest of it.

**Suppression is at the soft-alias site in `ParseStatementAST`, deliberately** —
that is the last point before the argument list is parsed. Anything further down
has already built the condition into the AST, and dropping a node then is how a
side effect survives a switch that promised to remove it. What remains is an
empty `AN_SEQ`, which is what `begin end` yields, so no lowering path needed a
new case.

**Measured against fpc 3.2.2, five rows, not one:**

```
                   default  {$ASSERTIONS OFF}  ON   {$C-}  {$C+}
  pxx                 1            1            2     2      3
  pxx --no-assertions 0            0            1     1      2
  fpc -Sa             0            0            1     1      2
```

`--no-assertions` reproduces FPC's column exactly. The default column differs by
the leading row only — every STEP matches — which is the ticket's deliberate
"default on" choice, kept: flipping it would turn every existing pxx assertion
into dead code with no diagnostic.

**`-Sa` is a no-op and that is the honest reading, not an accepted-and-ignored
flag.** It asks for assertions ON; ON is already our default. Asserted anyway,
because "accepted and inert" is precisely the shape the rest of this session was
spent removing, and a row that pins it is what tells the next reader the
difference.

**`--no-assertions` did not work when first written, and only a measurement
caught it.** `PasInitDefines` — which resets the lexer's directive state — runs
BEFORE `compiler.pas` walks `ParamStr`, so setting the flag in the CLI arm
changed nothing at all: the flag compiled clean and the program printed the
default column. The CLI arms now set `AssertionsVal` directly and the reset
still reads the flag, so the two stay in step if it is ever called twice. Noted
in the code at both ends.

**Two test files, and neither is sufficient alone.** The gating test's condition
has a SIDE EFFECT, because a row that only checks "nothing printed" passes on a
compiler that still evaluates the condition and declines to complain — which is
exactly the reported bug. And `test_assertions_directive_still_fires.pas` is the
counter-control: every row of the gating test would pass on a compiler that
dropped EVERY Assert, so one must still fail with FPC's 227. The expected value
(`1 1 2 2 3`) does not collide with the failure value (`1 2 3 4 5`), and the
pre-change compiler on this tree printed the failure value — that is the
negative control, measured rather than reasoned.

## Half 2 (the `(file, line N)` suffix) is still open — and the ticket's sketch of it is wrong

Measured under fpc 3.2.2, which the ticket's `Assertion failed (file.pas, line
12)` does not quite match:

```
  Assert(1=2, 'boom')          ->  boom (af.pas, line 4).            rc 227
  Assert(1=2)                  ->  Assertion failed (afn.pas, line 3).  rc 227
  ...with `uses sysutils`      ->  EAssertionFailed: boom (afs.pas, line 4)
```

So the message **replaces** `Assertion failed` rather than following it, the
default handler appends a `.` and a blank line, and the sysutils path carries
the composed text without the period. pxx today prints `Assertion failed: boom`
— a different line shape, not merely a missing position.

The work is threading the position to `__pxxAssert`
(`compiler/builtin/builtin.pas`), which today takes `(cond, msg)` and composes
`'Assertion failed: ' + msg` itself. The position is a compile-time constant, so
either the signature grows two parameters or the parser passes a pre-composed
message; the second needs AST surgery on the argument list, the first needs the
soft-alias site to inject two arguments. **Whichever is chosen, the composed
text must reach `AssertErrorProc` too** — otherwise sysutils' `EAssertionFailed`
carries a less useful message than the bare printer, which is backwards, and the
ticket already says so.

Unchanged from the original: this half is cosmetic parity, not a behavioural
bug. Re-typed accordingly — the `type: bug` on this ticket was for half 1.

## Parked 2026-09-04

half 1 (gating) landed in e4ee8048c; what remains is half 2, the failure-message shape, which is cosmetic parity — resume by threading the source position into __pxxAssert so AssertErrorProc receives the composed text too. fpc 3.2.2's exact output is recorded in the ticket body, measured, so do not re-derive it.

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.

## Half 2 (the message) landed 2026-09-04 too (frankS, Track P). Ticket closed.

**Landed the same session as half 1, in a separate commit, after measuring that
the ticket's sketch of this half was wrong.** The sketch said pxx should append
`(file.pas, line 12)` to `Assertion failed`. fpc 3.2.2 does not do that: the
message **replaces** `Assertion failed` rather than following it, and pxx's whole
line shape differed, not just the suffix.

Measured, four shapes, all now byte-identical to fpc 3.2.2:

```
  Assert(1=2, 'boom')            boom (af.pas, line 4).                   227
  Assert(1=2)                    Assertion failed (afn.pas, line 3).      227
  ...with uses sysutils          EAssertionFailed: boom (afs.pas, line 4)
  Assert inside {$i inc1.inc}    from-inc (inc1.inc, line 1).             227
```

**The include row is the one the ticket never mentioned and the one worth
keeping.** FPC names the INCLUDE's file and its own line, not the including
file's — `PasSrcOfTok` answers exactly that question, with a fallback to
`DbgSrcName` for the main file before its first range marker. The file is the
BASENAME (`sub/af.pas` prints `af.pas`), verified from a subdirectory, which is
also what makes the test rows independent of where `TESTTMP` lives.

**The trailing period belongs to the PRINTER, not to the message.** The default
path prints `text` + `.`; the hook path passes `text` alone, which is why FPC's
`EAssertionFailed` message has no period. Getting that backwards would have
looked right in the common case and wrong in the caught one.

**`__pxxAssert` grew a third defaulted parameter** `pos`, composed by the parser
at the soft-alias site (the position is a compile-time constant) and injected
into the argument chain after `Expect(tkRParen)`, before the type/overload pass
walks it — so it is checked like any other argument rather than smuggled past.

**`Assert(cond)` needs an EMPTY MESSAGE injected before the position, and that
has its own test row.** The parameters are `(cond, msg, pos)`, so appending one
node to a one-argument call lands the position in the MESSAGE slot: the failure
prints ` (f.pas, line 9)` with the message gone, which reads as a formatting bug
and is an off-by-one in the argument list. Inferring that row from the
two-argument one is exactly how it would have shipped.

**The hook gets the composed text**, which the ticket's own note demanded:
passing the bare message would leave sysutils' `EAssertionFailed` carrying LESS
than the bare printer does. `test_assert_raises_with_sysutils`'s expectation
changed accordingly and now names both `Assert` lines of its own fixture.

**The new fixture has filler above its `Assert` on purpose.** The line number IS
the assertion here, and an off-by-one — or a position read off the wrong token —
is plausible on line 1 and impossible on line 28. The full line is compared
rather than grepped for the filename, because the defect being replaced was a
line SHAPE and a `grep boom` passed on it throughout.

Two existing expectations moved with it (`assert_fail_b264.out`,
`test_assert_raises26`); both were pinning the old shape, and both now pin FPC's.
No other frontend calls `__pxxAssert` — NilPy's `assert` lowers to its own
if/raise tree — but the builtin is shared surface, so a NilPy and a C probe were
run against the signature change and are green.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
