---
track: P
prio: 80
type: bug
summary: "An unknown field on a BUILTIN-mirrored record (TSymbol/TParam/TProc, recIds 6/7/8) was accepted silently and stored at the tyInteger-at-offset-0 default, clobbering a neighbour. Only the compiler's own core structs are affected — user records were always checked — which is why it hid: it can only be hit by the compiler compiling itself."
status: done
owner: claude-P@opus5
---

# An unknown field on a BUILTIN record was accepted, and corrupted memory

- **Type:** bug (Pascal frontend, silent memory corruption + missing
  diagnostic) — **Track P** (member resolution, `symtab.inc`)
- **Found:** 2026-08-03 by claude-P@opus5 while completing
  [[bug-pascal-procvar-value-context-outside-assignment]]. The **FPC seed
  canary** in `tools/gate.sh quick` is what caught it — every pxx-side check was
  green.

## What happened

`TParam` (`defs.inc:953`) has no `ProcSig` field. This compiled clean anyway:

```pascal
Procs[ProcCount].Params[i].ProcSig := -1;      { symtab.inc, RegisterProc }
```

pxx built a working compiler from it. FPC refused the same source:

```
symtab.inc(5389,32) Error: identifier idents no member "ProcSig"
parser.inc(26814,30) Error: identifier idents no member "ProcSig"
ir.inc(2037,52)      Error: identifier idents no member "ProcSig"
```

The write landed at the not-found default — `tyInteger`, offset 0 — and
clobbered a neighbouring field. Two consequences in one build: the READ never
saw what the WRITE stored (so the feature silently did nothing), and
`test/quick_canary_nilpy.npy` **segfaulted** — an unrelated NilPy test in the
`quick` tier.

## Root cause

`TSymbol`, `TParam` and `TProc` are **builtin-mirrored records** — the compiler
carries hand-written layouts for its own core structs so it can self-host
(`symtab.inc:1114`):

```pascal
REC_TSYMBOL = 6;   REC_TPARAM = 7;   REC_TPROC = 8;
```

All below `REC_UCLASS_BASE = 16`. Two independent things then let the typo
through:

1. **`RequireRecMember` is gated on `recId >= REC_UCLASS_BASE`.** Its own
   comment states the assumption — *"Builtin records keep the lax path — their
   field names are compiler-authored"* — so it no-ops for recIds 6/7/8.
2. **The statement-lvalue path never calls it anyway.** There are only three
   `RequireRecMember` call sites and all three are expression paths; a
   breakpoint on the guard was never reached for `Syms[0].Bogus := -1`.

`RecFieldType` then fell out of its builtin-field loop and returned the
`Result := tyInteger` it was initialised with, at offset 0.

**This is why no minimal case reproduces it.** An ordinary user record gets
`recId >= 16` and is correctly rejected — four separate minimal shapes were
tried and every one errors properly. The bug is reachable only where a record is
builtin-mirrored, i.e. in the compiler's own source.

## Fix (landed)

Reject at the point the miss is decided, in `RecFieldType`'s builtin branch: a
builtin record's field names are compiler-authored, so a miss is **always** a
typo and never a legitimate probe. Falling through to offset 0 is never right.

That placement is deliberate — it is path-independent, so it also covers the
unguarded statement-lvalue path that `RequireRecMember` never sees.

### Verified

- `Procs[i].Params[j].<name>` for `ProcSig`, `Bogus` and `ZZZNoSuchThing` all
  now fail with `"<name>": no such member on this record/class`, naming the
  line; all three were silently accepted before.
- The compiler still **self-hosts to a byte-identical fixedpoint**, which is the
  real proof that no legitimate builtin-record field miss exists: a single false
  positive anywhere in ~120k lines of self-compilation would have failed the
  build.
- `tools/gate.sh quick` GREEN (self-host fixedpoint, testmgr quick, FPC canary).

## Residual — worth a follow-up, not urgent

`RequireRecMember` still only covers `recId >= REC_UCLASS_BASE`, and the
statement-lvalue path still does not call it. That no longer produces a silent
wrong store (the `RecFieldType` check catches those), but the three-call-site
asymmetry is a latent inconsistency: an unknown member on a USER record reached
purely through the lvalue path relies on other checks. Worth auditing the ~20
`AllocNode(AN_FIELD)` sites against the three guarded ones.

## Log
- 2026-08-03 — resolved, commit PENDING.
