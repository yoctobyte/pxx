---
track: N
prio: 45
type: bug
summary: "SILENT->CRASH: a local assigned instances of two unrelated classes keeps ONE static class identity, so every member access uses that layout. `o = DC(...)` then `o = PC(...)` reads o.native at DC's offset for both — a segfault when the layouts differ."
status: done
owner: claude-AN
---

# A local reassigned across two classes keeps one static class

```python
@dataclass
class DC:
    name: str
    native: Optional[Callable[[int], None]] = None

class PC:
    def __init__(self, name, native=None):
        self.name = name
        self.native = native

o = DC("a", plain)
o.native(1)          # SIGSEGV — before printing anything
o = PC("b", plain)
o.native(2)
```

CPython prints `plain 1` / `plain 2`.

## Measured, not inferred

`PXXDBG=n.locals` reports `<module> o tk=6 rec=1` — tk 6 is tyClass, so `o` is
a single STATIC class, NOT a variant. Both member accesses compile against that
one class's layout, and the access on the instance of the OTHER class reads the
field at the wrong offset and jumps through whatever is there.

A `PXXDBG` probe on the variant-field-call candidate scan confirms the other
half: `PyMakeVariantFieldCall` is never reached for this program. It is not the
dynamic-receiver path at all.

The layouts must DIFFER for it to bite — with `native` at the same offset in
both classes the wrong cast is harmless, which is why this hid behind
[[bug-nilpy-dynamic-receiver-callable-field-casts-to-the-wrong-class]] (whose
own repro was this shape by mistake; corrected there).

## Where it comes from

`PyCollectLocals` deliberately takes "the latest resolved class whenever it
differs" — added so that `with open(...) as f` followed by a later
`f = open(...)` would not keep the first round's class forever. That rule is
right for a name whose class is *refined*; it is wrong for one that genuinely
holds two unrelated classes, where the answer is that the local has NO single
static class and should be a VARIANT.

## Shape of the fix

Widen to a variant when two assignments resolve to unrelated classes (neither a
subclass of the other) — the same "no single answer, use the dynamic path"
conclusion the method/field scans reach. Note the cost: it moves such a local
onto the runtime-dispatch path, which is slower but correct, and it is the
representation CPython semantics actually require.

Check the sibling first: `PyWidenBinding` already exists for the type-kind half
of this question, so this may be one arm added there rather than a new rule.

## Gate

The program above matching CPython, plus a control that a local refined to a
SUBCLASS still keeps its static class (that is what the "latest resolved class"
rule exists for), plus the per-fix loop.

## Fixed (2026-08-08, claude-AN)

The repro now matches CPython. Getting there needed **three** changes, because
the ticket's "shape of the fix" was right about the rule and wrong about how
many places implement it.

### 1. The rule: unrelated classes widen to a variant

`PyCollectLocalsAST` / `PyCollectModuleLocalsAST` took "the latest resolved
class whenever it differs". Correct when the name is *refined* (one class is a
subclass of the other), wrong when it genuinely holds two unrelated classes.
Now: `IsSubclassOf` either way → keep taking the latest; neither → the name has
no single static layout, so `TypeKind := tyVariant`, `RecCi := -1`.

### 2. `Poly` — and why a flag, not `RecCi = -1`

The harvest runs to a FIXPOINT. Clearing `RecCi` alone lets the next round read
"no class known yet", re-adopt one, and report `changed` forever — it never
converges. So `TPyLocalConstraint` gains a sticky `Poly: Boolean`, never
cleared once set. All three creation sites initialise it.

### 3. Three mechanisms, not two — the reason the first fix did not hold

`PyNoteLocalType` is a THIRD place that decides a local's class identity, and
its `if RecCi < 0 then adopt` read the widening's cleared `RecCi` as "nothing
known yet" and put the class straight back. Measured, not inferred: with only
the harvest loops patched, a **third** assignment back to the FIRST class
flipped `PXXDBG=n.locals` from `o tk=22` (variant) to `o tk=6 rec=0` (Alpha)
again. Two-assignment repros passed; the three-assignment one did not.

Per `root-cause-over-microfix`: three mechanisms serving one concept is a design
flaw, and the honest fix was to make `Poly` authoritative in all three rather
than patch the two that the repro happened to reach. Collapsing them into one
binding routine is the real cleanup and is left for its own ticket.

### 4. The obsolete ambiguity guard behind it

With the receiver correctly widened, the ticket's repro stopped segfaulting and
started **failing to compile**: "`.native()` on a dynamically-typed value is
ambiguous (several classes declare that field)". That guard was dead weight —
`PyMakeVariantFieldCall` already re-scans every candidate class and emits one
`pyvarobj(v) is C ? <call as C> : ...` arm each, exactly as the sibling METHOD
path does. Both copies of the check (the procedural-signature pass and the
variant-field pass) now keep the first hit as the fallback arm and let the
callee dispatch.

Worth stating plainly: had the guard been left, this ticket would have traded a
segfault for a wrong-but-compiling program in one shape (`o.name` on the
second class read empty) — the expensive failure mode, not the cheap one.

### Verification

- Ticket repro: `plain 1` / `plain 2`, matching CPython (was: SIGSEGV before any
  output).
- New `test/test_nilpy_rebind_across_unrelated_classes.{npy,expected}` — the
  repro, a re-rebind back to the first class (the shape that exposed
  `PyNoteLocalType`), the **subclass-refinement control** that must keep its
  static class, and the plain non-class rebind control. `.expected` is CPython's
  own output. Wired into `test-nilpy` and `test-core`.
- Blast radius, all matching CPython: `test_nilpy_with_name_reuse` (the
  `with open(...) as f` reuse the old "latest class" rule was added for — it is
  two unrelated classes, so it now goes dynamic and still works),
  `test_nilpy_file_close_readlines`, `file_open`, `file_read`, `file_write_text`,
  `file_io_and_comprehensions`, `with_protocol`, `rebind_type`,
  `class_field_identity`, `boolop_class_identity`, `captured_class`.
- uforth (its dispatch table is a `native` Callable field, the exact path
  touched): compiles, smoke green, `testje.for` byte-identical to CPython.
- `tools/gate.sh quick` GREEN — self-host fixedpoint byte-identical.

### Follow-up filed
[[refactor-nilpy-three-places-decide-a-locals-class-identity]]

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.
