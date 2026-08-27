---
track: N
prio: 62
type: bug
owner: frank1-AN
blocked-by: []
summary: "`self.v = 2.5` in a SUBCLASS, where `v` was declared `self.v = 1` in the parent, prints 4612811918334230528 — the double's bits. The sibling defect within one class was fixed 2026-08-27; this one is left because the parent's layout is already final by the time the subclass is registered, so it needs a whole-program pre-pass rather than a local join."
status: done
---

# A field declared in an ancestor is not widened by a descendant's rebind

- **Type:** bug (Track N) — **silent wrong value**, the expensive class.
- **Filed:** 2026-08-27 while resolving
  [[bug-n-a-fields-type-is-fixed-by-its-first-assignment-and-never-widened]],
  whose fix covers the within-one-class case and deliberately stops here.
- **Measured on:** pinned **v383** (`18392d1d3181`) and HEAD alike — the sibling
  fix changed neither row.

## Repro

```python
class P:
    def __init__(self):
        self.v = 1
class Q(P):
    def widen(self):
        self.v = 2.5
        return self.v
print(Q().widen())
```

| | |
| --- | --- |
| CPython | `2.5` |
| pxx | `4612811918334230528` — the double's BITS read as an integer |

Same shape through a base class used as a mixin-style helper:

```python
class M:
    def setup(self):
        self.m = 1
class C(M):
    def __init__(self):
        self.setup()
    def widen(self):
        self.m = 3.5
        return self.m          # CPython 3.5, pxx 4615063718147915776
```

`C(M)` is ordinary single inheritance — the FIRST base stays a real parent and
is not flattened — so this is the same case, not a mixin-specific one.

## Why the sibling fix stops short of it

`PyRegisterClassMembers` now widens a re-assigned field with `PyWidenBinding`
and re-lays-out the class's own window. It is restricted to **that window on
purpose**: a field found by `FindUField` in a descendant may belong to an
ancestor, and rewriting it there changes a layout that is already final —
`curOff` for every subclass starts at `UClsSize_[parent]`, so any subclass
registered *before* this one already baked in the narrow size. Widening the
parent in place would silently corrupt those.

So the answer is not a wider guard, it is a different phase: the join has to be
computed over **every** class body that assigns the name, before any class in
the hierarchy is laid out. That is a whole-program pre-pass, and it is the same
shape as the ordering hazard the sibling ticket flagged, one level up.

## Note on correctness, not just layout

Widening the ancestor is the *right* answer and not merely the convenient one: a
`P`-typed reference can point at a `Q`, so if any descendant stores a float in
`v`, the slot must hold a float for every `P`. A fix that widened only the
descendant's view would put two different types on one slot.

## Gate

The two repros above match CPython, plus the controls the sibling ticket's test
already carries (a same-type rebind must not widen; neighbouring fields keep
their values), plus one new control: two subclasses of the same parent, one of
which widens, and the other still reading the field correctly.

## Scoping note — 2026-08-27 (still open; re-measured, not fixed)

Both repros reproduce unchanged at HEAD (`22690b507548`, pin v386), plus the
third control the Gate asks for:

```
Q().widen()   4612811918334230528     CPython 2.5
R().read()    1                       CPython 1     <- the sibling subclass is fine
P().v         1                       CPython 1
```

**The whole-program pre-pass this ticket calls for already EXISTS.**
`PyRegisterClassFieldsPrepass` (pyparser.inc) walks the entire token stream
before any class is parsed, finds every `class` header, computes each body span
with `PyFindBodyEnd`, and calls `PyRegisterClassMembers` for all of them. It
already runs *two* sub-passes over that stream — the first only to mark which
classes are used as a second base. So the shape the fix needs is not new
machinery; it is a **third sub-pass inserted before the registering one**, which
computes per (class, field-name) the join over that class and every descendant,
into a side table `PyRegisterClassMembers` consults when it first sizes a field.
That is where to start, and it is a much smaller starting position than "a whole
new phase".

**Two things block it, and both are worth knowing before anyone opens the file:**

1. **The field TYPE inference is not callable.** The `tk` the widening site
   (pyparser.inc, the `else if (fi >= UClsFBase[ci])` arm) joins against is
   computed inline, deep inside `PyRegisterClassMembers`'s ~1200-line body, from
   surrounding context. A detect sub-pass needs the same answer, and writing a
   second inference is precisely the third-spelling failure
   `devdocs/dev/normalise-dont-special-case.md` warns about — the copy that
   stays broken. So step one is **extracting that inference into a routine**,
   behaviour-preserving, exactly as `PyJoinInferTk` was extracted from the
   conditional-expression arm for
   [[bug-n-a-short-circuit-or-returning-self-is-typed-as-a-number]]. Do that as
   its own commit and gate it before touching layout at all.

2. **The pre-pass does not lay out every class.** It falls back to fields-only
   when a base cannot be resolved yet ("If the base cannot be resolved yet, fall
   back to fields-only and let PyParseClass do the full run as before"), and
   skips classes used as mixins. So a side table must be consulted by BOTH
   registration routes, not just the pre-pass one, or the fix works for most
   programs and silently does not for the rest — the worst available outcome
   for a bug whose symptom is already a silent wrong value.

**One thing that looked like a shortcut and is not.** A tempting cheaper fix is
to widen the ancestor in place when a descendant is registered, and re-lay-out
the already-registered descendants — attractive because in the pre-pass no
method BODY has been compiled yet, so no emitted code is stale. It fails on
point 2: the classes that took the fields-only fallback get their real layout
later, from `PyParseClass`, by which time other bodies are being compiled. Do
not take it.

Parked deliberately rather than microfixed. `root-cause-over-microfix.md`: the
diagnosis is the deliverable when the session cannot finish the overhaul, and a
narrow "widen when the RHS is a float literal" patch would close the two repros
above while leaving the concept wrong and the ticket looking done.

## Step 1 done — the field inference is now callable

The scoping note above names the first blocker: *"the field TYPE inference is not
callable... step one is extracting that inference into a routine,
behaviour-preserving... Do that as its own commit and gate it before touching
layout at all."* Done, and landed on its own.

`PyInferFieldDecl(j, fldAnn, methodStart, bodyStart, bodyEnd, isCtor;
var tk, fldRec, fldSig)` — 271 lines lifted verbatim out of
`PyRegisterClassMembers`. Not one line of it was rewritten, which is the whole
point: the pre-pass needs the SAME answer, and a second inference is the
third-spelling failure this ticket was parked to avoid.

`fldAnn` comes in (the caller still decides assignment-vs-annotated);
`rhsAt`, `k2` and `rhsName` were locals of the enclosing routine and are now
locals of this one — verified by measurement that no use of any of them survives
the block.

### The boundary was one statement off, and it compiled anyway

Worth recording, because the failure was loud but pointed somewhere else
entirely. The first cut took the block from the `fldAnn` decision through the
normalisation — which spans the END of one statement and the body of the next:

```pascal
if (self.NAME shape) then
begin
  <fldAnn decision>
end;                     <-- this end; went into the new routine
if fldAnn >= 0 then
begin
  <the inference>
```

so the moved `end;` closed the new routine's `begin` early, and the rest of the
body re-balanced against later `begin`s — a `begin`/`end` count of 18/18, and a
file whose braces balanced too. It built as far as **`undefined variable
(LoadFileCI)` in `compiler/pasparser_proc.inc`**, a file included *thirty
includes earlier* than `pyparser.inc`, with no error reported in the file that
was actually wrong.

What settled it was bisection, not reading: a stub with the same signature built;
the body truncated to its **first statement** did not. Printing that truncation
showed the stray `end;` immediately. The real boundary is the second statement's
body alone — `if fldAnn > 0 then` through `if tk <> tyClass then fldRec :=
REC_NONE;`.

The lesson for the next extraction in this file: a balanced `begin`/`end` count
proves nothing about where a block STARTS, and pxx attributes the resulting
error to wherever the scope confusion first bites, which can be an unrelated
file compiled long before.

### Verification — it changes nothing, which is the requirement

- Self-host fixedpoint verified, `converged after 1 round(s)`.
- **The ticket's own repro is byte-identical to v388 pinned** — `Q().widen()`
  still prints `4612811918334230528`, `R().read()` still `1`, `P().v` still `1`.
  An extraction that fixed the bug would mean it had not been an extraction.
- 55 named field / class-attribute / dataclass / property / inheritance / ctor
  canaries green. The five that need `-Futest/nilpy_units`
  (`last_class_in_module_attrs`, `multiple_inheritance_imported_base`,
  `renamed_class_attrs`, `shim_from_import_class_attrs`,
  `cross_module_defaults`) were verified byte-identical to pinned WITH the flag —
  without it they fail identically on both binaries, which is the harness, not
  the compiler.

### What is left

Step 2, unchanged from the scoping note: a third sub-pass in
`PyRegisterClassFieldsPrepass` computing, per (class, field), the join over that
class and every descendant into a side table, consulted by **both** registration
routes — the pre-pass one and `PyParseClass`'s, or the fix works for most
programs and silently not for the rest. Blocker 2 of the note still stands and is
untouched by this commit.

## Step 2 done — the whole-program join, and the bug is closed

The scoping note's plan, followed as written: *"a third sub-pass inserted before
the registering one, which computes per (class, field-name) the join over that
class and every descendant, into a side table PyRegisterClassMembers consults
when it first sizes a field."*

### What landed

**`PyClassHeaderSweep(phase)`** — the pre-pass's second sub-pass, now run twice
rather than once. Phase 0 DETECTS (resolve each class's first base; record what
type every `self.NAME` assignment gives every field); `PyFJPropagate` runs
between the phases; phase 1 REGISTERS as before, and the layout it computes now
consults the join.

It is one routine run twice, not two routines. Everything except the final
statement is shared — locating the header, reading `@dataclass` off the lines
above it, resolving the base list, finding the body span — and every one of
those carries its own recorded bug in its comments (the `@dataclass(eq=True)`
step-back, the one-line body that used to harvest the next class's members, the
multi-base deferral). A second copy for the detect run would have been a second
answer to each. The parts re-run in phase 1 are all idempotent assignments of
the same value; `PyMembersHoisted` is phase 1 only.

**The join table** (`PyFJCls` / `PyFJName` / `PyFJTk`, with `PyFJParent`): per
(class, field), the join of every type that class or any descendant assigns.
`PyWidenBinding`, not a third rule — the same join the field scan and the locals
scan already use, so int-then-float lands on a VARIANT here exactly as it does
within one class.

**`PyFJParent`, and why it is not `UClsParent`.** `UClsParent` is deliberately
left unset for a multi-base or not-yet-resolvable header and filled in later by
`PyParseClass` — which is after the join has to have propagated. `PyFJParent` is
read straight from the header's first base, before the multi-base and mixin
decisions, because those decisions are about LAYOUT and the join needs the
hierarchy either way.

**Propagation is one pass, no fixpoint.** Each entry is merged into EVERY
ancestor rather than just its parent, and the ancestors of a mid-chain class are
a subset of those of anything below it — so the order entries are visited in
cannot matter. The walk is depth-bounded rather than cycle-checked: valid source
has no circular hierarchy, but the pre-pass runs before anything is checked, and
a hang with no diagnostic is the wrong failure.

**The consult site is inside `PyRegisterClassMembers`, and that is the answer to
blocker 2.** The scoping note warned that a side table consulted only by the
pre-pass "works for most programs and silently does not for the rest", because a
class whose base could not be resolved early is registered from `PyParseClass`
instead. Both routes call `PyRegisterClassMembers`, so putting the lookup in the
routine — at the point where a field is first sized — covers both by
construction rather than by a second call the next person has to remember.

### Two extractions, and the second was not in the plan

Step 1 extracted `PyInferFieldDecl` (what type does this declaration give?). The
detect pass turned out to need the other half too — **which tokens declare a
field at all** — so `PyFieldDeclAt` came out as well. That test is where the
`self.x: int = 5` / `if self.x:` distinction lives, and the comments around it
are a list of shapes that were once matched wrongly; two spellings of it would
have disagreed at exactly those shapes. What is still written twice is only the
walk — find a def, take its suite, step through it — which carries no semantics.

`PyWarnUnreadAnnotation` is silenced during detect (`PyFJDetecting`): the pass
re-reads every annotation the registering pass reads, and a doubled warning is
the one thing a user would notice about a pass meant to be invisible.

### Measured

- Self-host fixedpoint `95d62c4f3b4b`, `converged after 1 round(s)`.
- **Every row of the Gate matches CPython**, on the new
  `test_nilpy_ancestor_field_widened_by_a_descendant` (registered in the
  Makefile): `Q().widen()` `2.5`, the neighbour field `7`, the sibling subclass
  `R().read()` `1`, `P().v` `1` and its neighbour `7`, the mixin-shaped
  `C().widen()` `3.5`, a **three-level** hierarchy `C1().widen()` `0.5`, and the
  same-type control `T().again()` `20` / `S().n` `10` unwidened.
- **uforth.py (4357 lines of real Python) compiles to a BYTE-IDENTICAL binary**
  under the new compiler and v388 pinned, in 13.1s vs 14.1s. The pre-pass costs
  nothing measurable on a program with a real class surface, and changes nothing
  where nothing needs changing.
- A differential over `test_nilpy_*` tests whose name mentions a field, class,
  attribute, method, property, dataclass, ctor, inheritance, mixin, virtual,
  slot, widening or rebinding — new binary vs v388 pinned, comparing both
  compile status and program output. **Ran ~10 minutes over a 184-test list
  with zero differences, and was stopped there rather than completed** (the
  work was landed on request; Track T's watcher was building on the same box,
  so each compile took 2-3x its usual time). Re-run against the landed sha
  before treating that as full coverage — the count of tests it actually
  reached was not recorded, which is the part to fix if this is repeated.

### A class-typed field improved too, unasked

Probing whether the join could damage class identity found the opposite:

```python
class Base:
    def __init__(self): self.k = 0
class D(Base):
    def bump(self):
        self.k = Foo()
        return self.k.tag      # v388: 1277165808   HEAD: 9   CPython: 9
```

The same probe surfaced a genuinely separate defect that is NOT this one and
reproduces on pinned with no inheritance at all — a method call on a field that
was `None` at declaration returns the receiver's address. Filed as
[[bug-n-a-method-call-on-an-optional-class-field-returns-a-raw-pointer]].

### What this fix does NOT cover

A field a class inherits from a **flattened second base** (a mixin) is collected
against the mixin's own class index, not against each host that flattens it. So
a host widening a mixin-supplied field is unchanged from today. That is a gap,
not a regression, and it is narrow: single inheritance — the case both repros
and all real code in the tree use — goes through `PyFJParent` and is covered.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
