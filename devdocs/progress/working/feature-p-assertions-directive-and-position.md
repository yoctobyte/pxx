---
summary: "HALF 1 DONE 2026-09-04 (gating: {$ASSERTIONS ON/OFF}, {$C±}, -Sa, --no-assertions; the condition is no longer evaluated when off, verified against fpc 3.2.2). WHAT IS LEFT is half 2, the failure-message shape: FPC prints `boom (file.pas, line 4).` — the message REPLACES `Assertion failed` rather than following it — where pxx prints `Assertion failed: boom` with no position. Cosmetic parity, not a behavioural bug; re-typed and re-ranked accordingly"
type: feature
track: P
prio: 30
status: working
owner: frankS
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
