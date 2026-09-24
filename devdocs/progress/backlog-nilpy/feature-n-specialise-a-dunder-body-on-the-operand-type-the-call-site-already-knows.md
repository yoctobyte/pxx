---
track: N
prio: 80
type: feature
blocked-by: []
summary: "A bare dunder operand (`def __add__(self, o)`) stays a variant because the call-site typer counts `.name(` calls and an operator is never spelled that way, so every `o.x` in the body runs the dynamic attribute protocol. Measured 2026-09-24 at HEAD: 2.7x (bare 0.48 s vs annotated 0.07 s for the accumulator loop inside a def). An operator-site arm was BUILT AND REVERTED: counting operators whose left operand is untyped vetoes every dunder, and skipping them is unsound -- a run-time-dispatched `xs[0] + xs[1]` with a duck-typed object then raises where CPython answers. BLOCKED on the operator dispatch path giving a class-typed operand the protection the METHOD path demonstrably has (getattr-called duck objects give CPython's answer there). Low payoff on lekkerzeilen: the arm typed exactly one dunder operand (Quat.__mul__.o).""
---

# Specialise a dunder body on the operand type the call site already knows

Measured 2026-09-15 at `4452ec0631a97c02`. One class, one method, one
annotation's difference:

```python
def __add__(self, o):              # 320 IR ops, 35 calls
def __add__(self, o: 'Vec3'):      #  41 IR ops,  2 calls
```

Wall clock, both arms identical source except the annotation, loop bound
annotated so no variant comparison allocates, work loop-carried, min-of-3
interleaved, 200k adds:

```
bare operand       0.5220 s
annotated operand  0.0508 s
ratio             10.27x
```

## Why it is a compiler opportunity and not just a guidance note

**`self.x` is already fast; `o.x` is not, and the difference is the RECEIVER's
resolution, not the field layout.** Measured, all four declaration styles with an
annotated receiver compile `v.x` to `field ival=8 tk=19 [offset=8]` — a
constant-offset load of a native double:

| declaration | `v.x` |
| --- | --- |
| `__slots__ = ("x","y","z")` | static offset |
| bare class-level `x: float` | static offset |
| `@dataclass` | static offset |
| annotated `__init__` | static offset |

So the layout machinery works. What fails is that `o` is a bare parameter, so
`o.x` cannot be resolved at compile time and the body degrades to dynamic
lookup and boxed arithmetic throughout.

**And the information is already present at the call site.** For `a + d` where
both are statically `Vec3`, the compiler knows the operand's class when it emits
the call — and then invokes a generically-compiled callee. Nothing about the
program is dynamic here; the type is simply not propagated across the call
boundary.

**The idiom guarantees the bad case.** No Python author annotates a dunder's
operand — `def __add__(self, other)` is what every codebase, every tutorial and
the data model documentation writes. So the slow path is not an edge case a user
wanders into; it is the only spelling in normal use.

## Shape of the fix — two options, the second is cheaper

1. **Specialise the callee per operand type** at call sites where the operand's
   class is statically known, keeping the generic body for dynamic callers.
2. **Emit a monomorphic guard in the generic body**: test the operand's class
   once on entry, and on a hit run a fast path with resolved offsets. One test
   per call instead of a dynamic lookup per field, and it also covers callers
   that do NOT know the type — which option 1 cannot.

Neither needs a language change and neither asks the user for an annotation.

## Corroboration from a real program

The lekkerzeilen seat disassembled their demo independently and found
`Vec3.__add__` at **6260 bytes with 210 calls and ZERO SSE floating-point
instructions**, and `Quat.rotate` at 24.7 KB with 864 call sites, for what is
about thirty multiplies and adds in source. An 80-sample leaf profile of the
same binary puts **25.0% of main-thread time in variant/attribute dispatch and
86% inside the pxx runtime**, with only 13.8% in anything nameable from the
demo's own source.

They also established what does NOT fix it: annotating locals, call sites,
constructors and method RETURN types moved that bucket from 25.0% to 23.8%, one
sample, against a pre-registered null — because all of those are outside the
method bodies where the cost lives. **This ticket is the one lever measured to
reach inside them.**

## IT IS NOT ABOUT DUNDERS — IT IS ANY UNRESOLVED RECEIVER, AND FIELD READS PAY MOST

Measured after the first write-up, same compiler, one class, four accessors:

| access | receiver | IR ops | calls |
| --- | --- | --- | --- |
| field `w.a` | `w: W` | 11 | **0** |
| field `w.a` | bare `w` | **87** | **8** |
| property `w.origin` | `w: W` | 22 | 3 |
| property `w.origin` | bare `w` | 25 | 4 |

**A field read on an unresolved receiver goes from ZERO calls to EIGHT.** A
property read barely moves, because a property is a call in both cases — so the
dynamic protocol is expensive relative to a FIELD and nearly free relative to a
CALL. The dunder operand is simply the commonest place a bare receiver meets a
field read in numeric code; it is an instance, not the rule. Retitle mentally as
"specialise on the receiver type the call site already knows" and the dunder
case falls out of it.

This also corrects a reading the lekkerzeilen seat and I both entertained: that
`@property` access was going through a dynamic lookup and that was the demo's
cost. With an annotated receiver a property read compiles IDENTICALLY to an
ordinary method call (22 ops / 3 calls each). Where their profile shows
`PyPropertyGet` inside the dynamic protocol, the receiver was not statically
known — same root cause, reached through a property rather than a field.

## Honest scope

The 10.3x is a fixture. The IR-op ratio (320/41) is structural and the
disassembly of real code is consistent with it, but **the transfer to the demo
is predicted, not measured** — the seat holding that tree is testing it, with
the same bucket pre-registered. Record the result here either way; a null would
mean the fixture ratio does not transfer and this prio is wrong.

**AND A BOUND ON IT ARRIVED BEFORE THE ARM DID, FROM THAT SEAT'S CALLER
ATTRIBUTION — IT ARGUES THIS PRIO DOWN FOR THEIR PROGRAM.** Walking rbp chains
on 58 of 70 samples and bucketing by the innermost DEMO-source frame,
`Vec3.__add__` **does not appear at all**; `Vec3.__iadd__` and `Vec3.create` are
one sample each. Their attributed time is `Grid.at` 13.8%, `World.number`
12.1%, `Vessel.__prop_get_state` 8.6%. So on THAT program the vector dunders are
in the noise and a 10x on them cannot move the frame rate much — which is
consistent with this ticket's mechanism being right and its headline INSTANCE
being the wrong one to rank on.

The mechanism is where the value is: 30 of 58 chains pass through
`pydynattr_get`/`pydynattr_has`/`pydynattr_get_v`, and each such read builds a
STRING KEY (`PyDynAttrKey` -> `pystr_of` -> `PXXStrConcat`) and probes a hash
table (`TPyDict.indexof`) — running declared-attribute, property, method and
dynamic resolution in turn, `Exception.Create` included, 3451 bytes of it, per
attribute per operation. **Rank this on the receiver-resolution mechanism across
all attribute access, not on the dunder fixture's 10.3x.**

## MEASURED ON REAL CODE — the mechanism is confirmed and it is bigger than the fixture said

The lekkerzeilen seat annotated the operand at fourteen definition sites and
disassembled the three hottest methods before and after. Pre-registered as P3:
the three `pydynattr_get_v` calls gone, better than half the bytes, and at least
three SSE instructions where there had been none.

```
method          before (bare operand)        after (annotated operand)
Vec3.__add__     6260 B, 210 calls,  0 SSE  ->   873 B, 18 calls,  3 SSE
Vec3.dot         6645 B, 225 calls,  0 SSE  ->   579 B,  4 calls,  5 SSE
Quat.rotate     24674 B, 864 calls,  0 SSE  ->  2175 B, 18 calls, 30 SSE

pydynattr_get_v calls:      3, 3, 9         ->     0,  0,  0
```

**`Quat.rotate` is eleven times smaller and makes forty-eight times fewer calls**,
and it grows thirty floating-point instructions where it previously had NOT ONE,
in a method whose source is nothing but floating-point arithmetic. Thirty is
about the flop count the source contains, so the "after" column is the program
the author wrote and the "before" column was an interpreter running it.

**This supersedes the fixture as the headline.** The 10.3x below stands as the
prediction that was made first and held; the rows above are the claim. All three
pre-registered thresholds were met and none marginally — which also means P3 is
not the kind of result a favourable-direction reading can manufacture, because
the direction and the magnitude were both written down before the build.

**It does NOT settle the frame-rate question and must not be quoted as if it
did.** The bound in the section above is unchanged: these three methods are in
that program's noise by caller attribution, so a 1.0x end-to-end result is
Amdahl and would refute nothing here. The two claims are independent — code
generation improves enormously (measured), and this program spends its time
elsewhere (measured). Where the mechanism would actually pay in that demo is
`Grid.at` (13.8%) and `World.number` (12.1%), **if their receivers are bare**,
which nobody has checked yet.

## Re-measured and narrowed (2026-09-24, frankb-12)

At HEAD, x86-64, the ticket's own `Vec3.__add__` shape, 200k adds, min of 3
interleaved: bare operand 0.60 s, annotated 0.22 s -- **2.7x, not 10.3x**. The
gap narrowed because call-site typing landed meanwhile:
PyParamTypeFromSites now types a bare parameter from what its call sites pass,
CLASS answers included when every site sits inside a def (`best >= 0`; a
module-level site gives up). Measured: `plus.o` with its site in `main()` prints
`tk=6 cls=Vec3`; with the same site at module level it prints `gaveup=1`. So
`Quat.rotate(v)`-style METHOD calls from inside defs are covered.

**What is still open is the OPERATOR spelling.** `PXXDBG=n.psites` on the
fixture prints `__add__.o mode=1 sites=0`: the site scan matches `.name(`, and
`a + d` is never spelled `.__add__(`, so a dunder's operand has no sites and
stays a variant. That is the whole remaining gap for dunders.

## Design -- operator sites for a binary dunder

In PyParamTypeFromSites' site loop, for mode 1 with `siteName` a binary dunder
(PyBinOpDunderName of some token T), also count a token of kind T as a site
when:

1. it is BINARY: the previous token ends an operand (ident, `)`, `]`, `}`,
   literal);
2. the LEFT operand is a simple primary (ident / `a.b` chain / call or
   subscript groups) not preceded by a higher-precedence operator, and it types
   (under the site's enclosing def, as the arguments already are) to the def's
   own class or a relative. Certainly-another-type (a number, str, another
   class) means another type's operator: skipped, not vetoed. Untypable counts,
   as an untypable receiver already does;
3. the RIGHT operand, the one argument, is the primary after T, and the token
   after it is not a higher-precedence operator (else the argument is a larger
   expression and the site is untypable, which gives up soundly).

The in-place spelling `a += d` is a site of `__iadd__`, and of `__add__` when
the class defines no `__iadd__`.

Soundness is the existing contract: a missed site can mis-type, and a counted
one only vetoes. Measured for the METHOD arm, which is already live: a
site-typed `o` (cls=Vec3) called from an UNSEEN caller (`getattr(a, "plus")(P())`
and `f = a.plus; f(P())`) with a DUCK-typed P whose fields sit at other offsets
(a str first, then z, y, x) gives CPython's `11.0 22.0 33.0`. So that path is
protected. The OPERATOR path is not yet known to be: with an ANNOTATED operand
(`o: 'Vec3'`), `xs[0] + xs[1]` where xs[1] is that P raised `TypeError: expected
a number, got int` (CPython: 11.0 22.0 33.0), and `xs[0] + 5` raised TypeError
where CPython raises AttributeError. **Re-run both probes on the operator arm
once it exists; if a site-typed operand behaves like the annotated one, the arm
must not land until the operator dispatch path gets the method path's
protection.**

## Built, measured, reverted (2026-09-24, frankb-12)

The operator-site arm above was implemented (PyOpSiteAt plus a hook in
PyParamTypeFromSites' site loop) and reverted before landing. It is
reconstructible from the design and helper spec above. Its fixture is kept
beside the build scratch; no copy in the tree.

1. **Counting every operator site vetoes everything.** Every `+` in numeric
   code is an operator token, `self.x + o.x` in the dunder itself included,
   and their left operands are untypable, so they count, and their untypable
   arguments veto: `__add__.o sites=1 gaveup=1`.
2. **Counting only sites whose left operand is CERTAINLY the class is
   unsound.** A visible `xs[0] + xs[1]` has an untyped left operand, so it is
   skipped; at run time it dispatches to `__add__` with a duck-typed P (fields
   at other offsets) and pxx raises `TypeError: expected a number, got int`
   where CPython prints `11.0 22.0 33.0`. The same duck object through the
   METHOD arm (`getattr(a, "plus")(P())`, and `f = a.plus; f(P())`) gives
   CPython's answer, so the method dispatch path protects a class-typed
   parameter and the operator path does not.
3. **Payoff on the target program is near zero anyway.** Compiling
   lekkerzeilen/sim.py (corpus 9db2e38) with the certain-left arm typed one
   dunder operand, `Quat.__mul__.o`. `Vec3.__add__` got zero sites, because
   real receivers are rebound locals (`a = a + d`), fields and attribute
   chains, never "certainly Vec3". The accumulator shape of this ticket's own
   fixture gets no sites for the same reason.

**What would unblock it:** make the run-time OPERATOR dispatch into a dunder
behave like the method dispatch when the operand's static class does not
match the object (find what the method path does; it was not located this
session). Then the certain-left arm becomes sound; a further step is typing
a receiver rebound only by the class's own operator (`a = a + d`).
