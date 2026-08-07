---
track: A
prio: 40
type: bug
summary: "A program built with BOTH --threadsafe and -dPXX_HEAP_DEBUG hangs at runtime; either flag alone is fine. The two debugging modes the runtime offers cannot be combined, which is exactly when you would want both"
---

# `--threadsafe` + `-dPXX_HEAP_DEBUG` hangs at runtime

- **Type:** bug (hang, debug tooling) — **Track A**
- **Found:** 2026-08-07, incidentally, while gating
  [[feature-a-managed-block-kind-word]].
- **Pre-existing** — the pinned binary hangs identically, so this predates the
  managed-block header change. Controlled, not assumed.

## Measured

```pascal
program ts1;
var s, t: AnsiString; i: Integer;
begin
  s := 'threadsafe';
  for i := 1 to 100 do s := s + '.';
  t := s;                 { share: refcount 2 }
  WriteLn(Length(s), ' ', Length(t));
  s := '';
  WriteLn(Length(t), ' survivor-ok');
end.
```

| build | result |
| --- | --- |
| `--threadsafe` | correct, exits 0 |
| `-dPXX_HEAP_DEBUG` | correct, exits 0 |
| `--threadsafe -dPXX_HEAP_DEBUG` | **compiles fine, then hangs** (killed at 60s) |
| same, on the PINNED binary | **hangs too** — pre-existing |

Compilation succeeds in every case; the hang is at run time.

## Why it is worth fixing despite the low priority

These are the runtime's two debugging modes, and the combination is precisely
the one a hard bug wants: a refcount problem that only appears under threading is
exactly what `PXX_HEAP_DEBUG`'s poison and quarantine exist to diagnose. Today
that combination is unavailable, and it fails by hanging rather than by saying
so — a session reaching for it would lose time to the tool before suspecting it.

## Not investigated

Whether it is the softlock (`PXX_TS_SOFTLOCK`) re-entering the heap lock from
inside a debug-path allocation, or the quarantine ring interacting with the
atomic refcount path. Both are guesses; measure before believing either. The
heap lock and the debug bookkeeping in `compiler/builtin/builtinheap.pas` are
the two places to look.

## Gate

Per-fix loop. A test that builds the repro above with both flags and asserts it
terminates with the right output — plus each flag alone, which must stay
correct.
