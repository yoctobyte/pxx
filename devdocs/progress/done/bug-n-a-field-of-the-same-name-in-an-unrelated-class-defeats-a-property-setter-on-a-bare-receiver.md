---
slug: bug-n-a-field-of-the-same-name-in-an-unrelated-class-defeats-a-property-setter-on-a-bare-receiver
type: bug
track: N
prio: 70
status: done
summary: "FIXED 2026-09-20 in compiler/builtin/pylib.pas: PyPropertySet, the write twin of PyPropertyGet, finds __prop_set_<name> in the receiver RTTI and is called from pydynattr_set BEFORE the shadow write. Was: `v.prop = x` on an unannotated receiver silently wrote a shadow attribute instead of running the @property setter whenever ANY declared class had a plain FIELD of that name, and the getter read the shadow back so the value looked right from outside. NOTE the precedence loop in PyVariantPropClass is UNCHANGED and still field-wins-across-unrelated-classes; this makes the fallback correct, it does not correct the scan."
owner: frankb-8e
---

# A same-named field in an unrelated class defeats a property setter

## The condition that springs it

`recv.prop = value` where `recv` has no static class, `recv`'s real class
declares `prop` as a `@property` with a setter, and **some other class —
any class in the program — declares a plain field named `prop`**.

`PyVariantPropClass` begins with a precedence loop over every declared class:
"a real FIELD of that name anywhere wins", exiting on the first class that has
one. That rule is right WITHIN one class (a field beats a dynamic attribute) and
wrong ACROSS unrelated classes, because it never asks whether the receiver could
be the class it found. With the property suppressed, the store falls through to
the dynamic-attribute path, which is STORE ONLY — there is no `PyPropertySet` —
so the setter never runs and the value lands in a shadow attribute.

`pydynattr_get` walks the shadow store BEFORE the declared fields and the
property, so the subsequent read answers from the shadow. **That is what makes
this silent:** the value reads back correctly at the call site while the object
the setter was supposed to write is untouched.

The compiler comment ~15 lines below that loop predicts this failure in its own
words, as the reason the AMBIGUOUS-property case keeps a loud refusal for a
store: *"falling through would turn this loud refusal into the silently-dropped
write ... and the getter would go on answering from the real backing field as
though nothing had happened."* The refusal was placed on one door and this door
was left open beside it.

## Measured 2026-09-20 against CPython 3.14.4

lekkerzeilen blocker 04, `devdocs/pxx-blockers/04-property-setter-skipped-through-bare-receiver/`.

| probe | shape | pxx |
| --- | --- | --- |
| repro | `Boat.throttle` is a property; `Engine.throttle` is a field | `(0.6, 0.0)` vs CPython `(0.6, 0.6)` |
| p2 | **only** `Engine`'s field renamed to `level` | `(0.6, 0.6)` — correct, the setter runs |
| p1 | bare-receiver READ of the property, no store | correct, reaches the getter |
| p3 | neighbouring fields after the bad store | intact — nothing is corrupted, the value goes to a shadow |

p2 is the discriminator: property, receiver and annotation are unchanged and
only the unrelated class's FIELD NAME moves.

## Why the population is large

The shape is property FORWARDING — a class exposing a component's value under
the same name — which is the commonest way the idiom is written. lekkerzeilen is
exactly that: `vessel.py:397` `@property throttle` returning
`self.propulsion.throttle`, against `sim.py:288` `self.throttle = 0.0` in
`Propulsion.__init__`. The demo's boat never moves: accumulated force comes out
`(0.0000, 4704.19, 0.0000)` against CPython's `(1333.01, 4707.28, 792.38)` —
vertical right, both horizontals exactly zero — and the frame still renders.

## Relation to the closed ticket

`done/bug-nilpy-property-setter-is-skipped-on-a-dynamically-typed-receiver` is
the same OBSERVABLE through a different door and its fix is intact: with no
name collision the setter runs. Filed separately rather than reopened, because
the condition is different and the closed ticket's summary is true.

## Family

Same cause family as
`bug-n-a-variant-field-is-claimed-as-the-callee-of-an-open-world-call-with-no-runtime-class-test`
(lekkerzeilen blocker 03): **a same-named member in an unrelated class claims a
dynamic receiver, with no runtime class test.** There it is a field claiming a
method call; here a field claiming a property store. Whoever fixes one should
read the other — the repair is the same, an is-test on the receiver with the
other path as the else arm, and the machinery for those arms already exists
(`PyMakeVariantIsTest`, used by the multi-candidate field and method paths).

A REFUSAL is the acceptable interim if the runtime arm is too big to land at
once: the ambiguous-property store next door already refuses and says "assign to
an annotated local first". A compile error is not a good outcome, but it is a
correct one, and this is a wrong value in a program that renders a clean frame.

## What would retire this

The repro printing `(0.6, 0.6)` unmodified, with `Engine.throttle` still named
`throttle`, and the ambiguous-store refusal next door still firing on its own
case.

## Workarounds for an application — and the rename is NOT one

**Annotating the receiver is the only local fix.** Renaming the colliding field
does NOT work in general, measured by lekkerzeilen-7a on 2026-09-20 after I
recommended it: the precedence loop scans EVERY declared class, so removing one
collision hands the win to the next one. Renaming `Propulsion.throttle` to
`_throttle` left the demo at 0.1 kn with the identical symptom, because
`app.py:514` has `self.throttle = 0.0` in a THIRD class, `Controls`, unrelated
to both the property's class and the component's. Renaming that one too — 13
sites in that class plus 2 `self.controls.throttle` reads — is what made the
boat accelerate.

So the workaround is not "rename the component's field", it is **"rename every
field of that name in every class in the program"**, and that is a property
nobody can hold. For an ordinary noun in a simulator — `throttle`, `current`,
`state`, `value` — a large program is close to guaranteed to have a collision
somewhere, and a NEW collision can be introduced by an unrelated class in an
unrelated module at any time. **A program that compiles and runs correctly today
can be broken by adding a field to a class it never references.** That is the
strongest argument for the runtime fix and against any compile-time
name-precedence patch.

7a's control is worth keeping beside this: the renamed tree run under CPython
gives the same 6.9 kn, so the rename did not change demo semantics and the two
compilers' numbers are being compared on identical source.

## PARKED 2026-09-20 by frankH, deliberately, with the fix specified

Not blocked, not waiting on anyone, and not abandoned — parked because of the
seat's own state, said plainly so nobody has to spend a turn asking.

**What is done.** The diagnosis above, four probes including two negatives, and
a fixture written and failing on exactly the right rows. The fixture lives in
this session's scratchpad and does NOT survive a reboot, so its source is
inline in this ticket; re-deriving it is twenty minutes, not an hour.

**What is next, concretely.** `PyPropertySet` in `compiler/builtin/pylib.pas`,
mirroring `PyPropertyGet` directly above it: find `__prop_set_<name>` in the
instance RTTI, read the value parameter's kind from `TMethInfo.ParamKinds`
(index 1 — index 0 is Self), and call the matching trampoline, returning False
when the kind is not one of the served set exactly as the getter does. Call it
from `pydynattr_set` BEFORE the shadow write, and from nothing else. The
accessor types and `PyPropertyGet` are declared AFTER `pydynattr_set` in that
file, so the setter needs a `forward` declaration rather than moving the type
block. The read path needs no change at all.

**Why parked rather than taken.** This is a change to the runtime attribute
path — it is in every compiled program, and its failure mode is a silent wrong
value, which is the class this ticket is about. The seat holding it had, in the
preceding hour: recommended a workaround that its own diagnosis on the screen
ruled out (the rename, refuted above); backgrounded a gate with `&` inside an
already-backgrounded call and read the wrapper's exit code over the job's, a
trap it had read the rule for the same evening; and censused a population of 91
where the recorded one is 67. All three were caught and none reached a commit,
which is the system working — and three in one stretch is a signal about the
seat, not about the system. A fix here that PASSES and means something slightly
different is the exact profile, and that is not a risk worth taking for a few
hours' earlier landing.

**For whoever takes it, including a later frankH.** Do not start from the
mechanism, start from the fixture: build it, watch it fail on the three rows it
should fail on, and only then write the setter. The row that passes `4.0` to a
clamping setter is the one that separates "the setter ran and wrote elsewhere"
from "the setter never ran" — keep it. And read the workaround section above
before proposing any compile-time repair.

## 2026-09-20, frankb-8e — THE INLINE FIXTURE IS NOT INLINE, AND THE REPRO IS STILL LIVE

**The parking note says "its source is inline in this ticket" and it is not.**
There is no code block anywhere in this file. That sentence is load-bearing —
it appears in the same paragraph that says the fixture lives in a scratchpad
which does NOT survive a reboot, so it is the safeguard, and the safeguard was
not taken. The twenty-minute re-derivation the note budgets is therefore the
floor, not the risk.

Recording it rather than quietly rebuilding, because the failure is the shape
this tree spends the most on: a ticket that ASSERTS a thing was preserved, read
by someone who then plans around it. The parking note is otherwise excellent and
the fix specification in it is exact; this is the one clause to distrust.

**Recoverable, and cheaper than twenty minutes:** the four probes exist in the
demo repo at `devdocs/pxx-blockers/04-property-setter-skipped-through-bare-receiver/`
(`repro.py` plus the three controls), which is not a scratchpad and does survive.

**Re-measured at compiler `05e1d35cd993`** (which carries the blocker-03 fix, so
this also establishes 03's repair did not touch this one — different function,
as expected):

| probe | CPython | pxx |
| --- | --- | --- |
| `repro.py` line 1 | `(0.6, 0.6)` | **`(0.6, 0.0)`** |
| `repro.py` line 2 | `0.9 0.9` | `0.9 0.9` |
| `control_annotated_param.py` | — | identical |
| `control_local_receiver.py` | — | identical |
| `control_module_level.py` | — | identical |

**A WARNING ABOUT READING THAT REPRO, because it cost me a wrong verdict first
time.** `repro.py` prints TWO lines and only the FIRST is the defect; the second
is the module-level store, which has always worked. I read it with `tail -1`,
got `0.9 0.9`, and briefly recorded all four probes as PASSING. **Diff the whole
output against CPython — never the last line.** This is the interesting element
not being last, in a file someone else wrote.

## THE AXIS THAT MAKES A REDUCTION PASS: A CONSTRUCTION AS THE ARGUMENT

**`drive(Boat())` PASSES. `b = Boat()` then `drive(b)` FAILS.** Same compiler
(`05e1d35cd993`), same classes, same property, same setter, everything else
identical — measured by bisecting from `repro.py` toward a reduction of mine,
one change at a time.

Handed a fresh CONSTRUCTION the frontend types the parameter from the call
site, so the receiver stops being dynamic and the property resolves statically.
The defect needs a receiver the frontend cannot narrow, and a bare name is one.

**THIS IS WHY A FIXTURE FOR THIS BUG IS EASY TO WRITE GREEN.** I wrote one
first with `drive(Boat())` — because constructing in the call is the natural
way to write a self-contained test — and it **passed on the unfixed compiler**,
reproducing nothing while looking like a complete four-row fixture with
controls. Had it been written after a fix rather than before one, it would have
certified this defect as repaired. The spelling is now pinned in a comment in
the fixture itself rather than left to whoever edits it next.

This is the CLAUDE.md rule about a minimal case fixing every axis you did not
think about, in the shape where the unenumerated axis is **how the argument is
spelled at the call site** — not the property, not the receiver's annotation,
not the collision, all of which this ticket already enumerates.

## Fixture, WRITTEN AND FAILING ON THE RIGHT ROWS, 2026-09-20

`test/test_nilpy_a_property_setter_runs_through_a_bare_receiver_despite_a_same_named_field.npy`
— not yet wired into `test-nilpy`, because it fails today. Oracle is CPython on
the same file. At `05e1d35cd993`:

| row | CPython | pxx | what it shows |
| --- | --- | --- | --- |
| `drive(b1)` | `(0.6, 0.6)` | **`(0.6, 0.0)`** | the setter never ran |
| `drive_clamped(b2)` | `(1.0, 1.0)` | **`(4.0, 0.0)`** | **the shadow cannot fake this** |
| `drive_annotated(b3)` | `(0.6, 0.6)` | `(0.6, 0.6)` | annotated receiver is fine |
| module-level `b.throttle = 0.9` | `0.9 0.9` | `0.9 0.9` | ordinary path intact |
| `set_controls(Controls())` | `0.25` | `0.25` | must-not-break: a plain field stays a plain field |

**The clamping row is frankH's and it earns its place.** A setter that clamps to
1.0 receiving 4.0 reads back `1.0` if it RAN and `4.0` if it did not. Every
other row here can be satisfied by a shadow attribute answering its own write —
which is precisely what makes this defect silent — so a fixture without that row
would go green while the setter was never called. `(4.0, 0.0)` is the
unambiguous signature: the 4.0 came straight back out of the shadow, unclamped,
and `propulsion.throttle` was never touched.

The third class `Controls` is in the fixture deliberately, per the workarounds
section above: it is what makes "rename the colliding field" fail to be a
workaround, and its own row must keep passing.

---

## RESOLVED 2026-09-20 (frankb-8e) — `PyPropertySet`, called before the shadow write

`compiler/builtin/pylib.pas`. The write twin of `PyPropertyGet`, which has sat
directly above it since the computed-attribute-name fix and had no counterpart:
find `__prop_set_<name>` in the receiver's RTTI, read the VALUE parameter's kind
from `ParamKinds[1]`, call through that convention. `pydynattr_set` calls it and
returns if it answers True.

**THE FIX IS IN A BUILTIN, NOT IN THE COMPILER.** `compiler/pascal26` came out
BYTE-IDENTICAL across this change — `05e1d35cd9930ea3` before and after, with
`converged after 1 round(s)`, so the fixedpoint really ran and really did not
move. Anyone verifying this by comparing compiler shas will conclude nothing
landed. The artefact that changed is the one every NilPy program compiles
against, which is why a `git pull` delivers it and a rebuild is not required
for THIS blocker (03, in `pyparser.inc`, does require one).

### The order is the fix, not just the call

`PyPropertySet` runs BEFORE the store, and that is load-bearing rather than
tidy. `pydynattr_get` consults the shadow store FIRST, before declared fields
and before the property. So a shadow write does not merely miss the setter — it
**masks the getter from that point on**. Writing first and calling second would
leave the mask in place even on the arm that works.

### Two ABI facts, both measured, both a SEGFAULT if guessed

**The accessors are FUNCTIONS, not procedures.** A NilPy `def` returns None,
None is a Variant, so the frontend emits every method — a property setter
included — as a function returning Variant. I wrote the five pointer types as
`procedure` first, on the reasoning that a setter returns nothing, and the
fixture **segfaulted**: a Variant return is passed by hidden result pointer, so
declaring it away shifts every argument by one and `recv` receives the sret
slot. The authority is `pyeval`'s `PyHostCall`, which has **no procedure arm at
all** — `TPMV_0_1 = function(self: Pointer; d0: Double): Variant` — and it is
the routine that already calls arbitrary NilPy methods by RTTI. I should have
read it before writing the types rather than after the crash.

**The kind comes from `ParamKinds[1]`, not from `RetKind`.** Index 0 is Self.
`RetKind` describes the None handed back, not the value accepted; a property is
free to take what it does not return, and the clamping row is a case where the
two disagree in value as well. Reading the convention off the wrong end of the
pair is the same crash by a different route.

Both are guarded rather than assumed: `Arity <> 2` declines, `RetKind <> 22`
declines, `ParamKinds = nil` declines, and any value kind not spelled out
declines. A decline falls through to the store, which is exactly today's
behaviour — the getter's own discipline, and here the penalty for guessing is a
shifted argument list rather than a wrong value.

### Verification

Fixture `test_nilpy_a_property_setter_runs_through_a_bare_receiver_despite_a_same_named_field`,
wired into `test-nilpy`. Oracle is CPython on the same file, so no expected
output is restated and no row's expected value is a default, a width or an empty.

| row | CPython | pinned v413 | after |
| --- | --- | --- | --- |
| `drive(b1)` | `(0.6, 0.6)` | `(0.6, 0.0)` | `(0.6, 0.6)` |
| **`drive_clamped(b2)`** | **`(1.0, 1.0)`** | **`(4.0, 0.0)`** | **`(1.0, 1.0)`** |
| `drive_annotated(b3)` | `(0.6, 0.6)` | pass | pass |
| `b.throttle = 0.9` literal | `0.9 0.9` | pass | pass |
| `set_controls(Controls())` | `0.25` | pass | pass |

**The clamping row is the fixture and the rest is scaffolding** (frankH's call,
and it was right). A store of 4.0 through a setter that clamps to 1.0 reads back
4.0 if the setter never ran — the shadow answering its own write, which is the
entire reason this defect was silent. Every other row is satisfiable by that
shadow.

**Positive control measured, not predicted:** pinned v413 `f94c2a7e2396d2be`
fails rows 1 and 2.

### TWO RESIDUALS, both left open deliberately

**A property with a getter and NO setter still shadow-writes instead of
raising.** CPython raises `AttributeError: can't set attribute`. We store, and
because the store is consulted before the property, the read-only property
silently becomes writable AND its getter stops being called. That is a real
divergence, it is adjacent, and it is NOT this ticket — fixing it means deciding
whether to raise, which changes behaviour for programs that rely on today's
answer. Filed separately rather than smuggled in here.

**Unserved parameter kinds decline silently.** A setter taking a kind outside
{Variant, int, double, string, Boolean} falls through to the store and is
therefore still broken, with no diagnostic. Same shape as the getter's, which
has carried it since it was written. A warning would be the repair; neither has
one.

### What this does NOT close

Nothing about the READ path, which already worked. Nothing about
`PyVariantPropClass`'s field-wins precedence loop — **the loop is still wrong
and still scans every declared class**, and this fix works by making the
fallback correct rather than by correcting the scan. That matters for anyone
reading the summary as "the precedence loop was fixed": it was not. The loop
sends the call site to `pydynattr_set`, and `pydynattr_set` now does the right
thing. A future fix to the scan would make this path colder, not redundant.

### A cost note, BANKED AND NOT CHASED

`PyPropertySet` runs on **every** store that reaches `pydynattr_set` — i.e.
every attribute write through a receiver whose class the frontend could not
name — and it builds `'__prop_set_' + name` and walks the RTTI before it can
decline. For a receiver with no property of that name, which is the common
case, that is an allocation and a failed lookup per store.

**It is symmetric with what the READ path already does:** `pydynattr_get` has
called `PyPropertyGet` on the same terms since the computed-attribute-name fix,
so this adds no new *class* of cost, only the write half of an existing one.

**NOT MEASURED, and deliberately not measured.** The owner's steering on
2026-09-20 is *"if framerate is still low it's worth profiling but let's not get
ahead"*, so this is recorded as a starting point for whenever that happens and
is not a line of work. If someone does open it: the cheap repair is to skip the
lookup when the receiver's RTTI carries no `__prop_set_` accessors at all, which
is a per-class fact and cacheable, not a per-store one.

Log: 2026-09-20 frankb-8e — resolved by PyPropertySet in compiler/builtin/pylib.pas, commit 12806ea63. Fixture and kind-coverage fixture wired into test-nilpy in the same commit; NilPy tier green at 1045 rows, gate quick GREEN.
