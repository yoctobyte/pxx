---
track: U
prio: 60
type: decide
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
