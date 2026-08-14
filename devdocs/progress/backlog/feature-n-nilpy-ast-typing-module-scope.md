---
track: N
prio: 55
type: feature
---

# NilPy: type MODULE locals from the AST too

Remainder of `feature-n-nilpy-ast-based-typing` (resolved 1a4089b4). Def and
method bodies now type their locals by parsing (`PyCollectLocalsAST`);
**module scope still uses the token scanner** `PyCollectModuleLocals` ->
`PyInferExprType`, so the drift this ticket set out to kill still exists at
module level.

## Why it was left

A def body is one parseable block with a known start token, so the trial parse
is a straight `TokPos := bodyStart; PyParseBlock`. Module scope is not: it
interleaves `def`, `class` and statements, and `PyCollectModuleLocals` walks it
with an indent-depth filter to skip anything nested. A trial parse would have
to run the whole program's top level — including registering procs and classes
— and roll all of that back, which is a much bigger blast radius than a body.

## Status: mostly LANDED (226f2507)

`PyCollectModuleLocalsAST` trial-parses the module body — enabled by
`PyRegisterDefShells` (ba546669), which registers top-level def signatures up
front so a module statement may call a def declared further down.
`PyCollectModuleLocals` is gone.

**What remains, and why.** Three narrowings keep the pre-pass off ground it
cannot stand on. Only the second is a real gap:

1. An annotated `name: T = expr` reads the annotation and skips the RHS —
   intended, and the escape hatch for everything else.
2. **A bare assignment whose RHS calls a method on a NAME (`x = c.two(1)`) is
   skipped.** Class MEMBERS are not registered until `PyParseClass` reaches
   the class, so trial-parsing it would fail on a method that is valid a
   moment later. Cost: no WIDENING for that name (the real parse still
   declares it).
3. Only assignments are parsed; nothing else declares a module local.

**To close (2): hoist class member registration the way def signatures now
are.** `PyRegisterClassMembers` already has a `fieldsOnly` flag and is
already run twice (fields pre-pass, then `PyParseClass`). The obstacle is
that the non-fieldsOnly path also appends to the `PyDc*` dataclass-default
tables, so a third run would duplicate them — untangle that first, then give
`PyParseClass` a "members already registered" guard.

`PyInferExprType` survives for ONE caller: the ctor field scan, which has no
parseable block of its own — fields must exist before any body is parsed. See
[[project_nilpy_class_pipeline_ordering]]. Closing that is the same
declaration-phase work as (2).

## Recon 2026-07-31 — confirmed still genuinely open, not stale

Given how many other tickets this session turned out to already be fixed,
re-checked this one for real rather than assuming. It is NOT stale — the
exact "x = c.two(1)" repro from item (2) above still reproduces:

```python
class C:
    def two(self, v): return v * 2
c = C()
x = c.two(1)
print(x)      # CPython: 2      pxx: 2.0
x = 3.5
print(x)      # both: 3.5
```

`x`'s first binding (`c.two(1)`, an int) gets silently widened to float
because the module pre-pass never saw it as a note-worthy assignment (the
method-call RHS is skipped, per item 2), so the LATER `x = 3.5` binding is
the only one the widening table learns about, and the whole slot renders
as float from the start — the exact "no WIDENING for that name" defect
this ticket already predicted, still present. Not attempted this pass:
the fix needs untangling `PyRegisterClassMembers`'s dual dataclass-table
role first (a real, if bounded, refactor of the class-member registration
pipeline), which is more than a quick patch and carries real risk of
subtly breaking dataclass defaults if rushed.

## 2026-08-09 — item (2) is DONE; re-scoped to what actually remains

Re-measured rather than re-read, because the 2026-07-31 recon above is now
stale.

### Item (2) — the `x = c.two(1)` narrowing — FIXED

```python
class C:
    def two(self, v): return v * 2
c = C()
x = c.two(1)
print(x)      # 2      (was 2.0)
x = 3.5
print(x)      # 3.5
```

Matches CPython on both lines. The obstacle the ticket named — "class MEMBERS
are not registered until `PyParseClass` reaches the class" — was removed by the
member pre-pass hoisting method signatures: `PyMembersHoisted` exists and gates
`PyParseClass`'s re-registration, which is exactly the "members already
registered" guard this ticket asked for. The `PyRegisterClassMembers`
dataclass-table untangling it warned about therefore does not block anything
here any more.

### Item (1) is not a gap
An annotated `name: T = expr` reading the annotation and skipping the RHS is the
intended escape hatch, as the ticket says. Nothing to do.

### Item (3) is the whole remaining ticket — and it has a shape now

*"Only assignments are parsed; nothing else declares a module local."* That is
still true, and tonight showed it is not one gap but a FAMILY: the depth>0 arm
recognises a short list of safe RHS token shapes, and every shape missing from
that list is a silent wrong value waiting. Three were found and fixed in one
session, all by running realistic programs rather than by inspection:

- `name = Cls(...)` inside a block →
  [[bug-nilpy-block-nested-scalar-then-class-rebind-loses-widening]]
- `name = other[k]` inside a block, a `.values()`/`.keys()` loop target, and a
  `list()`/`sorted()`/`reversed()` wrapper →
  [[bug-nilpy-module-name-reassigned-from-a-subscript-in-a-block-reads-garbage]]
- a tuple-unpack target list `a, b = ...` →
  [[bug-nilpy-tuple-unpacked-name-undefined-in-a-later-assignment]]

Each was cheap on its own. The point is that patching shapes one at a time is a
losing game: `.items()` (a two-name target) is still unhandled, and so is any
call that is not one of the three named wrappers.

**The real close is the one the arm's own comment already names**: a pre-pass
that does not `Error()`-and-Halt on an as-yet-unseen name, so the RHS can simply
be trial-parsed like everything else and the safe-shape list disappears. That is
what this ticket should become. Until then, every new shape is another silent
bug found by luck.

### `PyInferExprType` has SEVEN callers, not one
The ticket says it "survives for ONE caller: the ctor field scan". Measured:
seven, including the ternary arm, the sequence-repeat arm and the def
return-type chase. Removing it is a larger job than the ticket implies, and it
is not blocked on the ctor scan alone.

## 2026-08-11 — the FAILURE MODE of item (3) is closed; the CAUSE is not

Landed under [[bug-nilpy-name-bound-by-a-method-call-in-a-block-is-undefined-later]].

The 2026-08-09 note above says "every new shape is another silent bug found by
luck", and that is still the right reading — but it conflates two things the
safe-shape list was doing at once:

1. **Making a name RESOLVE** so a later statement's trial parse does not
   `Error()`-and-Halt. This half is now shape-independent. A block-bound name
   whose RHS matches nothing is registered as a **phantom**: a scratch symbol
   the harvest skips, so it resolves and asserts no type. `raw = f.read()`,
   `v = str(x)`, any call at all.
2. **Contributing a TYPE to the widening table.** Still shape-by-shape, still
   the losing game this ticket describes, and `.items()` is still unhandled.

Only (1) is fixed. The route this ticket names as the real close — a pre-pass
that does not Halt on an as-yet-unseen name — is unchanged and is what (2)
needs; `Error` still calls `Halt` directly, which is why the depth>0 arm still
cannot simply trial-parse.

**What the phantom changes for whoever takes this on:** the cost of an
unrecognised shape is no longer a compile error on ordinary Python. It is now
only a missing widening — the same cost item (2) of this ticket has always
carried. That makes the remaining work a correctness-of-types job rather than a
"the compiler rejects my file" job, and it should be re-priced accordingly.

Also fixed in the same arm and worth knowing before touching it: the safe-shape
tests matched on the FIRST TOKEN of the right-hand side only, so
`wrapped = "a-b".split("-")` was typed tyAnsiString off its leading string
literal and `len()` read garbage. `PyBlkRhsEndsAt` / `PyBlkRhsEndsAfterGroup`
now require a literal to be the WHOLE right-hand side. Any new shape added to
this list must ask the same question.

## 2026-08-14 (claude-A-N) — item (3)'s COST is closed, by re-reading what it costs

The 2026-08-11 note split item (3) into two halves and closed the first
(a name RESOLVES via a phantom). It described the second — "contributing a TYPE
to the widening table" — as still shape-by-shape and still the losing game.

That framing is what kept it open, and it is slightly wrong. The remaining
damage was never "we cannot type an unreadable shape". It was **"we type the
readable shape and pretend the unreadable one is not there"**, which is a
different and much smaller problem: an unreadable binding next to a readable one
means the name's type is UNKNOWN, and unknown next to known is not known.

### Measured first — two silent wrong values, both inside a block

```python
z = c.two(1)   # unreadable: a method call
z = 3.5
print(z)       # 4615063718147915776   <- 3.5's IEEE bits read as an integer
```
```python
y = "a-b".split("-")
y = 5
print(len(y))  # TypeError: expected a str, list, dict or bytes, got int
```

Both are the worst class: a plausible number and a wrong-type crash, from
ordinary Python, with no diagnostic.

### The fix is the INTERSECTION, not blanket widening

`PyUnkBindNames` records every name whose block-nested binding the arm could not
read. At the end of each round, a name in **both** that list and the constraint
table goes `tyVariant`. A name only in the list is left exactly as it is today.

That distinction is the whole design, and `PyPhantomNames`'s own note is why:
blanket tyVariant was tried before and **broke `tok is None` for a str-typed
Optional**. That failure is the single-binding case — which this does not touch,
and which is the first half of the new test, kept as a control.

### A missing literal shape was hiding half of it

The depth>0 readable list had `tkString`, `tkInteger`, list/dict literals and
name/arith forms — and **no `tkFloat`**, though the sibling scanner
`PyFieldTypeFromBlock` reads one. So `z = 3.5` inside a block put the name in the
table not at all, and the intersection had nothing to widen against. Added, with
`tkTrue`/`tkFalse` beside it. Worth noting as its own lesson: two scanners
answering the same question with different shape lists is the sibling-arm smell
`normalise-dont-special-case.md` warns about, and the difference between them was
invisible until a value came out wrong.

### What is still open, honestly

- The **route this ticket names as the real close** — a pre-pass that does not
  `Error()`-and-Halt on an as-yet-unseen name, so the RHS could simply be
  trial-parsed and the safe-shape list would disappear — is UNCHANGED. `Error`
  still calls `Halt` directly.
- What changed is the PRICE of not doing it. An unreadable shape no longer costs
  a wrong value; it costs a `tyVariant` slot where a narrower one would have
  done. That is a performance cost, not a correctness one, so this ticket should
  now be read as an OPTIMISATION item rather than a correctness one — and
  re-priced accordingly.
- `PyInferExprType` still has seven callers, per the 2026-08-09 note.

### Gate

`test/test_nilpy_block_unreadable_binding_widens.npy` + `.expected` from CPython
— the single-binding control, both measured shapes, each ordering of the pair,
the pair split across two blocks, a top-level target with an unreadable block
binding, and the bare float/bool literals. The four inference-lineage tests
re-run green. `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.
