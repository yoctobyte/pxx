---
prio: 70
status: done
owner: claude-N
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_function_values.npy red at 082e5175beba (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-07T19:07:49Z
- **Test source:** test/test_nilpy_function_values.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_function_values.npy'` at 082e5175beba23fab687e30f3c350899cf9134ef

## Range
bad `082e5175beba`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-304763/test_nilpy_function_values26  [code=1423865B  data=33604B  bss=9276B  procs=1226]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## RESOLVED 2026-08-08 — two gaps, and the second one was MINE

Two separate failures had to be cleared, and honesty about which is which
matters because they have opposite provenance.

### 1. A plain class's Callable field is unreachable through a dynamic receiver

`for x in words: x.native(vm)` failed to COMPILE — "no class declares a method
or callable field .native()". A procedural signature is recorded only for a
`@dataclass` field; a plain class's field takes its type from the `__init__`
parameter it is assigned from and records none, and the dynamic-receiver scan
REQUIRED one.

Fixed with a SECOND scan pass: a signature-less VARIANT field is a candidate
when no signed field matched. Deliberately a second pass, not a relaxed first
one, so every program that resolves today resolves identically. The call goes
out through `pyvar_callv<n>`, which tells the callable shapes apart at run time
and needs no signature; `PyMakeVariantFieldCall` now accepts `sigPi < 0` and
skips the arity check it cannot perform.

Two unrelated classes declaring the same field name remain a diagnostic rather
than a guess — the METHOD path has runtime class dispatch for that case
(`dualCis`) and the FIELD path still does not. That is the honest limit, and it
is why the new test lives in its own file: adding a second class with a
`native` field to `test_nilpy_function_values.npy` trips exactly that error.

### 2. An annotated Callable local assigned a bare def — a REGRESSION I INTRODUCED

`g: Callable[[VM], None] = w_ten` then `g(vm)` SEGFAULTED. `pinned` runs this
file correctly, so this was not pre-existing: my own Callable-field unification
this morning (making a `Callable` annotation yield a VARIANT) broke it. Two
causes, both mine:

- the annotated-assignment path parses its RHS with a bare `PyParseBoolExpr` —
  it never had the `PyMakeFuncValue` / `PyBoxCallableValue` treatment its
  unannotated twin (`g = f`) gets, so a bare def went into a variant slot as an
  unboxed code address;
- it also recorded the annotation's proc SIGNATURE on the local, which makes
  the call site marshal the name as a procedural value — a typed indirect call
  straight through the 16-byte slot. A FIELD keeps its signature deliberately
  (it is the "this field is callable" marker); a LOCAL has no such need.

Sibling branches again: one rule, two statement spellings, only one of them
had it.

**This also corrects a claim I filed earlier today.**
[[bug-nilpy-plain-class-callable-field-unreachable-through-a-dynamic-receiver]]
says "PRE-EXISTING, reproduced under pinned". That is true only of the shape I
tested there (a class-level `native: Optional[Callable[...]] = None` annotation
ALONGSIDE a ctor parameter). The shape in THIS test — a field typed purely from
an annotated ctor parameter — runs fine under `pinned`, so for it the compile
failure was mine.

## Verified

New `test/test_nilpy_plain_class_callable_field.npy`: the field through a
for-in variable, a dict value, an untyped parameter and a static receiver, plus
the annotated local and its unannotated twin. A/B'd against MY OWN change —
disabling the two edits reproduces the compile error — because `pinned` passes
this file and so cannot serve as the control.

`testmgr --tier full` GREEN for both this job and
test_nilpy_for_two_names_over_a_variant. `make test-uforth` PASS, self-host
byte-identical, `tools/gate.sh quick` GREEN.
- 2026-08-08 — resolved, commit PENDING-COMMIT.
