---
summary: "Implement FPC assertion parity: {$ASSERTIONS ON/OFF} and -Sa gating (Assert compiled OUT when off, so its side effects do not run), plus the '(file, line N)' suffix FPC appends to the message"
type: feature
track: P
prio: 40
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
([[bug-p-assert-does-not-raise-eassertionfailed]], done).

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
