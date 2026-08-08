---
track: U
prio: 45
type: decision
---

# Decide: how should NilPy dispatch dunders on a Variant-held instance?

- **Type:** decision (Track U) — escalated, not guessed
- **Opened:** 2026-08-01. Blocks
  [[feature-nilpy-runtime-dunder-dispatch-on-variants]] and, through it, three
  tickets that share its root.

## The fork

Dunder dispatch is compile-time only. Once an instance is inside a Variant — a
container element, a widened global, a Variant parameter — no dunder fires:
`[a, b]` prints `[, ]`, `sorted()` raises, `box[0] + box[1]` raises. Three
tickets are stalled on this and would otherwise each grow their own private
runtime path.

## Options

**A. Runtime dunder dispatcher over the RTTI method table.** Look up the dunder
on the object's actual class and call it.
- Covers every case, including ones not yet imagined.
- Needs an argument-passing convention and a Variant-returning shim per dunder.
- Puts a reflective lookup on arithmetic and repr — the hot paths.

**B. Compile-time guarded dispatch.** Emit a tag test plus a direct call where a
Variant might hold a class.
- No reflection, cheapest at run time.
- Needs the candidate class set, which the Variant erased; does not cover
  containers, the most visible symptom. Partial by construction.

**C. Per-class dunder table registered at construction.** pylib looks up a
function pointer by (class, dunder).
- No reflection on the hot path, no static candidate set needed.
- Costs a table plus registration, and a decision about which dunders are in it.

## Recommendation

**C**, with A as the fallback for dunders left out of the table. It is the only
one that covers containers without putting reflection on the arithmetic path,
and the table is a bounded, reviewable artifact.

If the cost of the table is unattractive, A is the honest alternative — B should
not be chosen believing it fixes these three tickets, because it does not fix
the container one at all.

## What is NOT being asked

Whether the compile-time static paths stay: they should. They are correct, fast,
and already landed. This is only about what happens when the static class is
genuinely unknown.

## POSTPONED — 2026-08-03 (user)

> "postpone, i need to study this"

Second deliberate postponement (the first was 2026-08-01 on the sibling
[[decide-nilpy-runtime-dunder-dispatch-mechanism]], "#1 needs a careful
thought"). Still blocked on judgement, not on information. **Do not answer this
from the analysis below** — it costs less than the options imply, which is an
argument about cost, not the judgement being reserved.

### Carry forward: measured against HEAD, so the fork is narrower than drafted

Read out of the emitters rather than reasoned about:

1. **Option C's stated cost is not real.** It is written as "a table plus
   registration, and a decision about where it hangs". There is already a
   reserved **16-byte metadata area immediately before every VMT** — `[VMT-8]`
   the RTTI backlink, `[VMT-16]` the managed-field layout backlink — and NilPy's
   class emitter (`pyparser.inc:17193`) mirrors the Pascal one (`parser.inc`
   ~24619) with a comment to keep the two in step. A dunder-table backlink at
   `[VMT-24]` is that pattern extended by one word, **patched at emit time**.
   There is no registration at construction.

2. **Option A's dependency is absent, not merely unproven.** RTTI emission is
   published-only ("every class with >=1 published member",
   `compiler/rtti_emit.inc`). NilPy classes declare no published members, so
   **no RTTI blob is emitted for them at all**. A is therefore: first build RTTI
   emission for every NilPy class, then put a name search on the arithmetic hot
   path, then live with
   [[project_rtti_method_table_multi_consumer_stride_landmine]].

3. **The obvious way to do C is a trap, and it should be named on the ticket.**
   A synthetic common base (`TPyObject`) with virtual dunders reuses the
   existing `AN_VIRTUAL_CALL` machinery and reads clean. But virtual dispatch is
   deliberately gated on `PyClassInHierarchy` (`pyparser.inc` ~8223): a class
   with neither parent nor children gets a **direct** call, because "the method
   is resolved on that very type is what Python means anyway". A universal base
   makes that predicate true everywhere and turns **every** NilPy method call
   into a VMT indirection. The backlink shape leaves `UClsParent = -1`.

4. **The constraint that narrowed the space is free under C.** The
   carry-forward on the sibling ticket requires answering "does this class
   declare `__bool__`?" cheaply at run time for objects that mostly do not. Under
   a slot table that is a single nil test, and nil is where the correct default
   ("any instance is true") already lives — so no raise, no reflection, and
   option 4's inapplicability to truthiness stops being a constraint.

5. **Scale.** ~50 Python dunders appear in the frontend
   (`grep -oh '__[a-z_]*__' compiler/*.inc`, minus the C/compiler ones like
   `__attribute__`). The three stalled symptoms need about ten — `__repr__
   __str__ __bool__ __eq__ __hash__ __lt__ __le__ __gt__ __ge__ __len__`. At 8
   bytes a slot that is a few hundred bytes per class that declares any dunder,
   and zero for classes that declare none.

### Left open deliberately, and worth deciding WITH the mechanism

- **Per-dunder fallback semantics.** A nil slot means "default", but the correct
  default differs per dunder: `__bool__` → true, `__eq__` → identity, the four
  ordering ones → raise. That is a semantics decision living inside the
  mechanism decision, and collapsing them is how a silent-wrong path survives.
- **Whether `[VMT-24]` is genuinely free.** It widens a layout two emitters
  currently keep in step at 16 bytes. Not measured — the blast radius should be
  checked before the shape is committed to, not after.

## 2026-08-07 — the one UNMEASURED thing is now measured: `[VMT-24]` is free

The carry-forward above closes with *"Whether `[VMT-24]` is genuinely free. It
widens a layout two emitters currently keep in step at 16 bytes. Not measured —
the blast radius should be checked before the shape is committed to, not after."*

Measured, by building it rather than reading it. Applied throwaway, gated,
**reverted** — nothing of this is committed, because the decision is still yours.

**The whole blast radius is three lines.**

| what | where |
| --- | --- |
| write the prefix (NilPy classes) | `pyparser.inc` — `for i := 0 to 15` → `23` |
| write the prefix (Pascal classes) | `parser.inc` — the same loop, kept in step |
| the layout-backlink guard | `rtti_emit.inc` — `if UClsVMTOffset[ci] >= 16` → `24` |

Everything else addresses **negatively from the VMT** and is therefore unaffected
by prepending a word: `rtti_emit.inc` patches `UClsVMTOffset[ci] - 8` and
`- 16`, and the only runtime reader is `builtin.pas`'s `PPxxPtr_(PtrUInt(vmt) -
8)^`. Nothing indexes forward from the start of the prefix — `UClsVMTOffset` is
taken *after* the prefix is written, so every virtual slot index is unchanged,
and `is`/`as` keep comparing VMT addresses exactly as before.

**Results with the prefix at 24 bytes:**

- **Self-host converges.** `gate.sh quick` reports the fixedpoint RED, and that
  reading is a false alarm worth recording: the check seeds from `$PINNED`, so
  round A is built by a compiler that predates the layout change. A ≠ B, but
  **B == C byte-identical** (`462a1ffe…`), which is the fixedpoint. This is the
  ordinary one-time-reseed signature of any layout change and is what
  `make stabilize` / `make pin` exist for — not non-convergence.
- **`testmgr --tier quick` PASS**, FPC seed canary PASS.
- **23 class-using `.npy` tests still diff clean against CPython.** The two that
  do not are pre-existing: `test_nilpy_dataclass` is byte-identical to `pinned`,
  and `test_nilpy_callable_to_str_param_fails` is a deliberate compile-failure
  test.
- Cost: **+8 bytes on the compiler binary**, and 8 bytes per class in `Data`.

So option **C**'s cheapest shape — a dunder-table backlink at `[VMT-24]`,
patched at emit time, no registration at construction — carries no hidden layout
risk. That was the last open cost question; what remains is judgement, which is
what this ticket has always been waiting on.

**Also re-verified at HEAD, so the option analysis is not quoting a stale tree:**
option A's dependency is still absent — `rtti_emit.inc` is published-only
("every class with >=1 published member") and `parser.inc` still sets
`UMthPub := 0` for a NilPy method, so no RTTI blob is emitted for a NilPy class
at all.

**Dunder census at HEAD** (the "~50" above): 47 Python dunders appear in the
frontend. The ten the stalled tickets need are `__repr__ __str__ __bool__
__eq__ __hash__ __lt__ __le__ __gt__ __ge__ __len__`.


## DECIDED 2026-08-08 (user): option B only, and PARKED

> right now i really tend to B only - keep it fast. the A case is rare and only
> serves weird edge cases.. we are a compiler after all, not an interpreter. if
> we could detect it and either halt compiling or have a clear runtime error we
> are good for now, and park this issue to postponed.

**Option B — compile-time guarded dispatch.** Option A (a reflective RTTI walk
on arithmetic and repr) is rejected: it taxes the hot path to serve rare cases,
and reflection is an interpreter's answer.

### Three refinements agreed while deciding

1. **B needs no reflection at all.** The world is closed, so the COMPILER knows
   every class declaring a given dunder. It can GENERATE one dispatcher — a
   switch on class identity to a direct call — and install it where the runtime
   needs it (pylib's container renderer takes it as a hook, exactly as
   `PXXObjFinalizeHook` is installed today). Compile-time table, one indirect
   call, no name lookup at run time.

2. **"Several candidate classes" is the NORMAL case and must NOT halt.** A
   heterogeneous list whose elements both define `__repr__` is ordinary Python.
   Some paths already refuse it — *"ambiguous (several classes declare that
   field) - assign to an annotated local first"* — which rejects reasonable
   code. B handles it with a tag test. Reserve the hard failure for **no class
   declares the dunder at all**.

3. **Silence is the one outcome ruled out.** `print([a, b])` currently prints
   `[, ]`: not slow, not loud, just wrong. Under B it is either correct or a
   clear error — the standing HALT-rather-than-be-silently-wrong rule from
   [[decide-nilpy-class-attribute-instance-read-model]].

### Detection reuses the hasattr precedent

The user's framing: *"for hasattr we did something similar - if nothing modifies
the class, can stay compiler. but as soon a class is dirty, we have to adapt at
the cost of slower code."* That predicate already exists —
`PyDynAttrEverAssigned` (pyparser.inc ~8604), the program-wide "this name is
dynamically assigned somewhere" scan. Clean class => closed-world dispatch;
dirty => degrade. **Reuse it rather than inventing a second notion of dirty.**

### Status: PARKED to rainy-day

Not scheduled. If anyone picks up a piece, the narrow one comes first: pylib's
container renderer has no ROUTE to dispatch that already works — measured
2026-08-07, `o.__repr__()` on an untyped parameter and over a heterogeneous list
both reach the right class today. That is a HOOK, not a dispatcher, and it is
most of the visible pain
([[bug-nilpy-list-of-custom-objects-loses-repr-str]]).

### Its dependent decision is answered too

[[decide-nilpy-runtime-dunder-dispatch-mechanism]] was `blocked-by` this one and
asks the same question one level down (how to dispatch when the class is known
only at run time). Option B answers it: a compile-time-generated switch on class
identity, not a lookup. Closed with a pointer here.
