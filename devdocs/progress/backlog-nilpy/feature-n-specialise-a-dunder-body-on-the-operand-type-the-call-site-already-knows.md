---
track: N
prio: 80
type: feature
blocked-by: []
summary: "An attribute read on a receiver whose class is not statically known runs the FULL dynamic protocol — a field read goes from 0 calls to 8, building a string key and probing a hash table. The call site usually knows the type already. Measured on real code: annotating the operand took Quat.rotate from 24674 B / 864 calls / 0 SSE to 2175 B / 18 calls / 30 SSE, and zeroed pydynattr_get_v in all three hot methods. Dunder operands are the commonest instance, but the rule is the receiver, not the dunder."
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
