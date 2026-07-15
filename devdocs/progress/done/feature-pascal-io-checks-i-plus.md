---
summary: "{$I+} I/O checking: EInOutError / RE on failed Text ops — third sibling of the landed {$Q+}/{$R+}; carries a DIALECT-DEFAULT question for the user"
type: feature
prio: 40
---

# {$I+} / {$IOCHECKS ON}: raise on Text I/O failure

- **Type:** feature (FPC-parity runtime checks). **Track A** (+ textfile RTL).
- **Status:** done
- **Opened:** 2026-07-15 night, straight after {$R+} completed — the probe:

```pascal
{$I+} assign(t,'/nonexistent/dir/f'); reset(t);   { FPC: EInOutError }
```
FPC 3.2.2: caught=1 (and {$I+} is FPC's DEFAULT). pxx: reset silently
no-ops (IOResult reports it, {$I-} style — pxx currently behaves as
permanently {$I-}).

## Design (the {$Q+}/{$R+} pattern, with one twist)

- Directive family: {$I+}/{$I-} single-letter (mind the {$I file} include
  form — same disambiguation dance as {$R}), {$IOCHECKS ON/OFF}, per-token
  TokIChecks, statement-anchored.
- TWIST vs Q/R: the IO ops are ORDINARY RTL CALLS (textfile.pas
  Reset/Rewrite/Append/Close/Erase + TextWrite/TextWriteLn/TextReadLn) —
  there is no single IR op to tag. Emit the check at the CALL SITE: when a
  statement-position call resolves to one of those procs (and the text
  read/write rewrites in ParseTextWriteRest/ParseTextReadRest), sequence a
  `PXXIoCheck` call after it. PXXIoCheck (textfile or builtinheap):
  if LastIOResult <> 0 then hook-raise EInOutError (4th hook,
  PXXIoErrorHook installed by sysutils) else 'Runtime error <code>' —
  FPC halts with the IO code itself as the runtime-error number.
- IOResult must still CLEAR on read per FPC semantics — check interaction
  with the existing SetIO/LastIOResult machinery (textfile.pas).

## DIALECT-DEFAULT QUESTION (user call — do not decide unilaterally)

FPC defaults to {$I+}; pxx today behaves {$I-} everywhere. Options:
(a) keep pxx-lax default (quiet, IOResult-style) with {$I+} opt-in —
matches the meta-dialect contract's lenient-default rule; (b) flip to
FPC's default under --mimic-fpc only; (c) flip globally (would change
failure behavior of every existing program/demo silently — riskiest).
Recommend (a)+(b). Cf. the float-exception-mask decision where the user
explicitly chose quiet-by-default (feature-float-exception-mask-control).

## Acceptance

- The probe matches FPC with {$I+} regions; {$I-}/default keeps today's
  IOResult behavior (per the user's dialect call).
- Hook family test extended; conformance sweep stays green.

## Log
- 2026-07-15 — resolved, commit 8135f170.
