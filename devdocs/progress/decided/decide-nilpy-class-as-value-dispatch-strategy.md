---
track: U
prio: 5
type: decide
blocked-by: []
summary: "A variant tag cannot make `cls(...)` callable — NilPy ctor params are statically INFERRED per class, so two classes of the same arity have different ABIs. Choose: compile-time candidate dispatch, an RTTI-driven runtime marshaller, or a uniform variant ctor ABI for classes used as values."
---

# How should a class used as a VALUE be called?

Blocks the fix for three tickets that all currently record the *same* plan, and
that plan does not work:

- [[bug-nilpy-a-class-used-as-a-value-segfaults-or-refuses]] (N, prio 60 — top of
  the N queue)
- [[bug-nilpy-calling-a-non-callable-segfaults]] (N, 55)
- [[bug-n-a-type-name-is-not-a-first-class-value]] (N, 45), and behind it
  [[feature-nilpy-six-and-warnings-shims]] (B, 45)

## The measurement that forces this decision (2026-08-09, HEAD 3e7a6b792)

All three tickets conclude that what is needed is **a distinct variant tag** for
a class reference (tag 11 is free; `VT_BOUNDFN_TAG = 10` is the last one used).
A tag is necessary. It is **not sufficient**, and the reason had not been
measured:

```python
class A:
    def __init__(self, v): self.v = v
class B:
    def __init__(self, s): self.s = s
A(3); B("x")
```

```
PXXDBG=n.ctorargs
  A trial=0 [0]kind=1,tk=1     <- __init__ param 0 is an INTEGER
  B trial=0 [0]kind=2,tk=4     <- __init__ param 0 is an ANSISTRING
```

**NilPy constructor parameters are statically inferred per class from the call
sites.** So two classes with the *same arity* have *different ABIs*. A registry
— `handlers = {"a": A, "b": B}`, then `handlers[k](x)` — cannot be called
through one code pointer, no matter how well the value is tagged. Tagging fixes
*recovering* the class; it does nothing about *calling* it.

This is why the existing `AN_METACLASS_NEW` lowering does not generalise either:
it reads the instance size and VMT from the RTTI blob at run time (so the CLASS
is dynamic), but its argument lowering runs through `IRLowerCallArg(cpi, ...)`
against a **statically known ctor proc index**. Dynamic class, static signature.

## The fork

### Option A — compile-time candidate dispatch (recommended)

At a call site `cls(args)` where `cls` is a variant classref, emit a runtime
switch comparing the payload against the RTTI blob address of each candidate
class, and under each arm emit the ORDINARY statically-typed construction that
`A(args)` would have emitted.

- **Correct by construction** — every arm is the existing, already-gated
  construction path, so the ABI cannot be wrong and no new marshalling exists.
- Reuses `AN_METACLASS_NEW` per arm; no runtime work, no new RTL surface.
- **Candidate set** = the classes whose ctor accepts the argument shape at this
  site. A class in the registry that does not fit gets a runtime "TypeError"
  arm rather than a compile error — which is also what CPython does.
- **Cost: code size.** O(#candidates x #call-sites). A 30-class NilPy program
  with a handful of dynamic call sites is fine; a large one is not obviously
  fine, and nobody has measured it.
- **Cost: closed-world.** A class reference arriving from a separately compiled
  `.py` module must still be in the candidate set. Whole-program compilation
  makes this true today, but it is an assumption worth naming out loud.

### Option B — RTTI-driven runtime marshaller

`TMethInfo` already carries `Arity`, `RetKind` and `ParamKinds` (a `^array of
Int64` type-kind words), and `PyFindDunder` already walks the class RTTI at run
time — so the runtime *can* discover the ctor's exact signature.

- Genuinely open-world; one implementation, no per-call-site code growth.
- **Cost:** turning a discovered signature into a call means placing arguments
  in target registers by kind — a per-target trampoline. Six backends. There is
  inline-asm support on all six, so it is possible, but it is new low-level
  surface in the RTL and the kind of thing that is subtly wrong on exactly one
  target for a year.

### Option C — a uniform variant ctor ABI for classes used as values

Compile a SECOND entry point per class whose parameters are all `Variant`, and
give the classref tag that entry's address. Calling is then uniform.

- No trampoline, no code-size blowup, open-world.
- **Cost:** which classes get the shim? All of them (pay for every class) or
  only those observed used as a value (a whole-program analysis, and it is wrong
  the moment a class reference is computed rather than named). Plus every
  argument crosses a variant boxing boundary the direct path does not, so
  `A(3)` and `cls(3)` have different conversion semantics — the "two mechanisms
  for one concept" smell that `normalise-dont-special-case.md` warns about, and
  that has already bitten this frontend repeatedly.

## Recommendation

**Option A.** It is the only one of the three whose correctness is inherited
rather than argued, and the code-size worry is measurable before committing:
count classes and dynamic call sites in the real targets (html5lib, tinycss2,
songformatter) rather than reasoning about it. If a real program shows the blowup
is bad, C becomes interesting for exactly the classes A struggles with, and B
stays the last resort.

Note it also stages nicely: A with a single-candidate set is already the useful
case (`cls = A; cls(3)`), and the registry case is the same machinery with more
arms.

## Not part of this decision

`str`, `int`, `bytes` as values ([[bug-n-a-type-name-is-not-a-first-class-value]])
are a separate representation question — they are not user classes and have no
RTTI blob, so they need a payload space of their own (a small type code) whatever
is decided here. Worth deciding together, but it does not block: the `six` shim's
blocked names (`text_type = str`, `binary_type = bytes`, `string_types = (str,)`)
are all BUILTIN types, so that half turns on the builtin-type-code question, not
on this one.

---

## CORRECTION 2026-08-10 — this is not a new problem; NilPy already solved it for DEFS

Everything above frames the argument ABI as an open three-way design fork. It is
not. **The identical problem — inferred, per-callee, mutually incompatible
argument ABIs — already exists for functions, and the frontend already solved it
and shipped it.** The options section argues *against* the uniform-variant route
on "two mechanisms for one concept" grounds; that is the route NilPy actually
took for defs, and it took it in the way that avoids that smell.

Measured at HEAD (`8adc552b5`), both programs run correctly today:

```python
def fa(v): return v + 1        # inferred: v Integer
def fb(s): return s + "!"      # inferred: s AnsiString
table = {"a": fa, "b": fb}     # one dict, DIFFERENT parameter ABIs
table["a"](10)  # 11    OK
table["b"]("y") # y!    OK
```

```python
def fa(v): return v + 1
fa(3)      # direct   OK
g = fa
g(10)      # indirect OK   <- SAME entry point, not a second one
```

The mechanism is **`PyDefUsedAsValue`** (pyparser.inc ~19469). It scans the
module for the def's name used as a bare value; if found, that def is compiled
with **variant parameters and a variant result** (pyparser.inc:21991 states it
in as many words: *"PyDefUsedAsValue normalises a def: variant result, variant
parameters"*). Every `Callable[...]` site then marshals the same way whichever
def it receives.

Note what it does NOT do: it does not add a second entry point. It normalises
the def's ONE entry, selected by the use-as-value scan — which is exactly why
the direct call `fa(3)` and the indirect `g(10)` both work with one conversion
path. Option C above proposed a *second* all-variant entry and was then
(correctly) criticised for creating two conversion semantics. That criticism
does not apply to what the def path actually does.

**There is no `PyClassUsedAsValue`.** The class path simply never got the
treatment its sibling has had for a long time.

### What this leaves genuinely open

The decision is much smaller than the options above suggest. Of the three
pieces:

- **recovering WHICH class** — needs the tag (tag 11). Unchanged, uncontroversial.
- **dynamic instance size + VMT** — **already solved**; that is precisely what
  `AN_METACLASS_NEW` does today.
- **the argument ABI** — the only open piece, and it has a working precedent to
  copy (`PyClassUsedAsValue` -> normalise the ctor's params/result to variants)
  rather than a design to invent.

So the real question is no longer "A, B or C" but: **is there any reason the
ctor cannot follow the same normalisation a def gets?** Candidate reasons worth
checking before committing — none yet investigated:

- a ctor is reached through `AN_METACLASS_NEW`'s allocate-then-call shape, not
  a plain indirect call, so the normalised ctor has to be callable from that
  path too;
- `__init__` has the implicit `self` receiver, and the bound-method history
  above (`bug-nilpy-bound-method-cannot-pass-through-a-callable-parameter`)
  shows the receiver is exactly where the procedural-type marshalling ran out of
  room before;
- inherited / overridden `__init__` across a hierarchy, where the def case has
  no analogue.

If none of those bites, this stops being a Track U decision at all and becomes
ordinary Track N work: "give classes the `PyDefUsedAsValue` treatment". It
should be re-filed into N in that case — U holds open questions, not work.

**Do not implement Option A or B off the analysis above without first
establishing why the def route does not apply.** That analysis was written
without noticing the def path existed.

## SUPERSEDED 2026-08-10

Re-filed as ordinary Track N work: **[[feature-nilpy-class-as-a-value]]**.
Nothing here needs a human decision — the trigger is missing, not the design.
Kept only as the record of how the wrong framing arose. Prio dropped to 5.

## MOVED TO decided/ 2026-08-11 — record only
Superseded and re-filed as work (see the SUPERSEDED note above). Kept as the
record of how the framing arose; nothing here awaits a human decision.
