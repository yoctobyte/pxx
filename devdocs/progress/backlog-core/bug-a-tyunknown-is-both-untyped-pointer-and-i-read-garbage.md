---
prio: 40
track: A
type: bug
blocked-by: []
summary: "tyUnknown is simultaneously the legitimate 'untyped Pointer' pointee sentinel and the value every unwritten/recycled slot reads back as. A consumer cannot tell 'this parameter genuinely takes anything' from 'I read a slot that is not mine', and because the permissive answer is the shared one, every such guard fails OPEN."
---

# `tyUnknown` means both "untyped pointer" and "I read garbage"

- **Type:** bug (latent; a sentinel that cannot distinguish *absent* from
  *invalid*). **Track A** — `defs.inc` / `symtab.inc`, the shared type model.
- **Filed 2026-08-30** by frankA, out of
  [[bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching]],
  which is the first *measured* instance. That ticket is fixed; this is the
  reason it was silent rather than loud, and it is independent of that fix.

## The collision

`tyUnknown` (ord 0) carries two unrelated meanings on a pointee field:

1. **"the pointer is untyped"** — a genuine `Pointer` formal, which legitimately
   accepts any argument. `ProcRetPtrElemTk` documents this as its own convention:
   *"pointed-at TTypeKind ord when the result is a typed pointer (**tyUnknown
   otherwise**)"*.
2. **"nothing wrote here"** — the zero an unset array slot holds, and the value a
   **recycled symbol slot** reads back as once some unrelated symbol occupies it.

A consumer sees ord 0 and cannot tell them apart. Worse, meaning (1) is the
**permissive** one, so the guard **fails open**: on garbage it does not refuse,
it *allows*.

## The measured instance

`MatchParamCompatible` narrows the blanket `tyPointer <- tyClass` rule by asking
what the parameter points at. It read `Syms[Procs[i].Params[j].SymIdx]`, whose
slot `SymRollbackTo` had already handed back:

```
REG   proc=GetPropInfo i=0 sym=363 elemtk=5 (tyRecord)  name=cls kind=2 (skParam)
MATCH proc=GetPropInfo j=0 sym=363 ptrelem=0 (tyUnknown) name=o   kind=1
```

`o` is the calling program's own variable. The guard read ord 0, concluded
"untyped pointer, permitted", kept the `PClassRTTI` arm viable, preferred it over
the exact class match, and `GetPropInfo(AnObject, 'Caption')` **segfaulted**.

Had the two meanings been distinct, the same stale read would have been an
immediate internal error naming the exact problem, instead of a segfault in a
user program three layers away.

## Why it is filed and not fixed here

Separating them is a type-model change, not a call-site change: a distinct
`tyInvalid`/`tyUnset` ord, every producer taught which one it means, and every
`<> tyUnknown` test audited for which of the two it actually intended. Several
of those tests are correct *today* precisely because the two collapse. That is
an A-lane change with a real audit attached, and it should not ride along inside
a P-lane bug fix.

## What to check when it is taken

- `ProcRetPtrElemTk`, `ProcParamPtrElemTk`, `SymPtrBaseTk`, `UFldPtrElemTk` and
  `AliasPtrBaseTk` all use ord 0 for "not a typed pointer". Each needs deciding
  separately: *absent* is legitimate for some and impossible for others.
- The per-proc init loop in `RegisterProc` writes `Ord(tyUnknown)` as the
  explicit default for the parameter columns. With a distinct sentinel that
  default becomes `tyUnset`, and *that* is what makes a missed write detectable.
- The general rule this is an instance of: **a sentinel shared between "legally
  empty" and "never written" cannot be checked**, and if the shared value is the
  permissive one the failure is silent. Any new parallel array should pick a
  default that is *invalid*, not one that is *allowed*.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick`; the audit above is the work, so
the real gate is that every converted `<> tyUnknown` test states which meaning it
tests for.
