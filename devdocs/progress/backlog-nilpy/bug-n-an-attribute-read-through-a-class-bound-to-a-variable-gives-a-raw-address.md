---
slug: bug-n-an-attribute-read-through-a-class-bound-to-a-variable-gives-a-raw-address
track: N
type: bug
prio: 80
status: backlog
owner: frankuser
created: 2026-09-11
found: 2026-09-11
found-by: frankZ
tags: [nilpy, values, silent-wrong-value, lekkerzeilen]
blocked-by: []
summary: "SEGFAULTS (rc=139), and the summary said ~5.5e6-with-exit-0 until 2026-09-13 -- a probe written to the old wording checks a VALUE and CANNOT observe a crash. WHERE IT DIES, measured at 7990405c2 with -g -O2 and the .map: __pxxInheritsFrom at `mov (%rax),%rax` reading the parent at +8, with the class pointer equal to 0x40000000 -- MSTR_STATIC_RC / PXX_STATIC_RC_FLOOR, the never-free REFCOUNT sentinel. A refcount word is being walked as a class pointer, so the fix is an OFF-BY-HEADER-OFFSET and not a wrong slot offset. (gdb frame #1 resolves to PyBoxClassRef and is noise -- no CFI, and that return address follows an exception-frame call.) THE OLD 5.5e6 IS EXPLAINED AND RETIRED: frankz-9c traced it to pyclsattr_bind registering the slot at ~5.6e6, i.e. the bound slot ADDRESS surfacing as the value. TRIGGER IS POSITION, NOT COUNT: anything lexically PRECEDING the accessed class, an `import` included -- and an import emits nothing, which also rules out "more than one emitting construct"; a statement AFTER the class is harmless, which rules out the last-class hoist-drain family a second way. AND THE OUTCOME IS SENSITIVE TO THE CLASS NAMES (Other, Self, Value, Count, Rtti, Result, Kind give the right answer; Bbb, Index, Data, Node, Entry, Base, Zzz, Bar segfault; `other` passes and `OTHER` fails). A semantic property cannot depend on an identifier spelling, so THE DEFECT IS PRESENT IN EVERY ROW AND ONLY THE CRASH IS CONDITIONAL ON LAYOUT -- which is what reconciles this ticket's three recorded observables as one defect. A row that prints the right answer is NOT evidence the bug is absent, and no fixture here may assert a value. Deterministic: three recompiles byte-identical, five runs agree. ROUTE: PyClsAttrRefGet, documented in pylib as the route for a class held as a VALUE, is NEVER CALLED in either the failing or the working case (frankz-9c, instrumented on entry); pyclsattr_inst_get is ruled out too. Identical under pin v408 and at HEAD, so the three class-as-value fixes of 2026-09-13 neither caused nor fixed it. OWNED by frankuser from 2026-09-13."
---

## Summary

See the frontmatter. Split from
`bug-n-a-class-reached-through-a-unit-alias-is-not-a-value`, which keeps the
method-call arm.

## Why it is two bugs and not two faces of one

| | this ticket | the other arm |
| --- | --- | --- |
| observable | wrong VALUE, silent, exit 0 | REFUSAL (`AttributeError`) |
| construct | attribute READ | method CALL (`@staticmethod`, `@classmethod`) |
| imports | **dependent** | needs no import, no package, no alias |
| about binding? | needs a differently-named binding | yes, `g = gl; g.s()` |

Only the second is about binding alone. They were filed as one because both
were first seen through a unit alias, which neither of them actually requires.

## What blocks the demo, and it is the OTHER one

frankZ corrected the ranking argument at `201131b40`: lekkerzeilen's seam writes
`gl = _backend.gl`, the **same-name** spelling, which resolves. So the corpus is
hit by the method-call arm, not by this one. **This arm is worse in KIND and the
other arm is what blocks goal 4** — rank them on different things and say which.

## The reproduction condition was wrong in three published statements

Recorded because the way it was wrong is the reusable part, not the condition.

1. frankZ: "a module-level assignment preceding the class". Too narrow on both
   axes.
2. frankuser: **could not reproduce it at all**, on the same binary
   (`c53cb51926a2`), and correctly declined to retire the arm on a miss.
3. frankZ, corrected at `201131b40`: a differently-named binding **and** any
   preceding construct, a docstring included.

**frankuser's miss was not a measurement failure — it was a MINIMISATION
failure**, and the minimised program is the one everybody writes first. See
`devdocs/dev/debugging-playbook.md`, "minimising a repro can delete the
condition".

## First step for whoever takes it

Not a re-reproduction: that is done, three times, by two seats. Find the site
that yields the class's storage ADDRESS where a read-through was meant. The
magnitude tracking program layout rather than field order is the discriminator
that says it is not an index bug.


## Re-measured 2026-09-13 (frankZ) — STILL LIVE, and the OBSERVABLE in the summary above is STALE

Measured at HEAD (`e5cd18e4b` in) and under pin v408, **identically**. It is not
a regression from today's three class-as-value fixes, and it is not fixed by
them.

**The observable is now a SEGFAULT (rc=139), not a raw address with exit 0.**
The summary's `~5.5e6 with no diagnostic` no longer reproduces; the program dies
on the read. Whoever picks this up should not go looking for a wrong NUMBER.
(The magnitude in the old report is explained below and is still a good clue.)

**The trigger, sharpened — it is not "a construct preceding the class".**
Measured by varying one line in the DECLARING module:

| declaring module contains | `w = m.Widget; w.V` |
| --- | --- |
| the class ALONE | **1 — correct** |
| the class + a bare `# comment` | **1 — correct** |
| a docstring, then the class | segfault |
| `B = 5`, then the class | segfault |
| a `def`, then the class | segfault |
| an `import`, then the class | segfault |
| TWO classes — reading EITHER one | segfault |

So the rule is **a module holding more than ONE top-level EMITTING construct**,
not position and not precedence: with two classes the FIRST one fails too, and it
has nothing before it. A comment is not a construct. Adding a TRAILING statement
after the class changes nothing, which rules out the last-class hoist-drain
family (`bug-n-the-last-class-in-a-module-reads-every-attribute-as-zero`).

**Isolated to ONE shape.** Through the same binding, in a module that triggers it,
all of these are CORRECT: the qualified read `m.Widget.V`; a `@staticmethod`
`w.st()`; construction `w()`; an instance attribute `w().n`; an instance method
`w().inst()`. Only the class-ATTRIBUTE read through the class-valued variable
fails. So the classref payload is sound — construction uses it successfully.

**The runtime route is NOT the one the code comments predict, and this is the
part that should save the next seat the most time.** `PyClsAttrRefGet` in
`compiler/builtin/pylib.pas` is documented as the route for "a class held as a
VALUE", and it is **NEVER CALLED** — instrumented with a WriteLn on entry, it
does not fire in the failing case OR in the working one. Meanwhile
`pyclsattr_bind` DOES fire and registers a sane address: `ZBIND name=V
cls=5538536 addr=5622640 kind=13` in both. **So the bind table is correct and
something else reads the attribute.** Note the address magnitude — ~5.6e6, which
is exactly the old report's ~5.5e6, so the original "raw address" reading was
very likely the bound slot's ADDRESS surfacing as the value.

Ruled out as the route: `PyMakeClsAttrInstGet`/`pyclsattr_inst_get`, which only
fires for an attribute REDECLARED in the chain (`n > 1` declaring classes) and
this repro has one.

**What is left to find:** what `w.V` actually lowers to for a class-valued
receiver with a single declaring class. That is the dynamic-receiver attribute
path `e5cd18e4b` landed in on 2026-09-13, so read that commit first. I did not
attempt the fix — the diagnosis is banked rather than microfixed, and the code is
hours old and another seat's.

## 2026-09-13, frankuser: the FAULTING INSTRUCTION, and the 5.5e6 number is retired

Taken after frankz-9c routed this to e5cd18e4b's lowering. The route is not that
lowering, and the crash has a precise address.

**Where it dies.** `-g -O2`, gdb, addresses resolved through the `.map`:

    #0  0x426eac  __pxxInheritsFrom   (starts 0x426d98)

    426e99:  mov  -0x20(%rbp),%rax     ; the current class in the walk
    426ea0:  add  $0x0,%rax
    426ea6:  add  $0x8,%rax            ; +8 = PXX_RTTI_PARENT
    426eac:  mov  (%rax),%rax          ; <-- SIGSEGV
    rax = 0x40000008

So the class pointer being walked is **`0x40000000`**, and that is not garbage
and not an address: it is `MSTR_STATIC_RC` (`defs.inc:123`) /
`PXX_STATIC_RC_FLOOR` (`builtinheap.pas:302`), the never-free REFCOUNT sentinel
that marks a statically allocated object. **A refcount word is being walked as a
class pointer**, so whoever fixes this is looking for a place that hands
`__pxxInheritsFrom` a header base off by the distance between the RC word and the
class/VMT word -- not for a place that computes a wrong slot offset. The same
signature is already documented one door along in `pylib.pas:1133` (`the object
jumped through 0x400000003`), where a destroyed VMT produced it.

Do NOT trust gdb's frame #1 here. It resolves to `PyBoxClassRef+0x53`, and the
disassembly shows that return address follows `call 0x427da1`, an exception-frame
setup, not a call to `__pxxInheritsFrom`. There is no CFI, so the backtrace past
frame #0 is noise. Frame #0 is the only reliable row.

## The trigger, corrected in two places

Against the version recorded above and against frankz-9c's note:

| shape | rc |
| --- | --- |
| lone class, nothing before it | 0 (correct) |
| `B = 5` before the class | 139 |
| `def f()` before the class | 139 |
| `import sys` before the class | 139 |
| another class before it | 139 |
| a statement AFTER the class only | 0 (correct) |

So it is **position, not count**: something lexically PRECEDING the accessed
class. An `import` is enough, and an import emits nothing -- which rules out
"more than one top-level EMITTING construct" as the characterisation, and rules
out the last-class hoist-drain family a second way.

**And the outcome is sensitive to the class NAMES, which is the important part.**
Holding the structure fixed at two classes and varying only the second class's
name: `Other`, `Rtti`, `Self`, `Result`, `Value`, `Count`, `Kind` give the
CORRECT answer; `Bbb`, `Index`, `Data`, `Item`, `Node`, `Entry`, `Base`, `Zzz`,
`Bar` segfault. `other` passes and `OTHER` fails, so it is not case-insensitive
name matching. A lone class named `Other` and a lone class named `Bbb` emit
byte-identical sizes, so `Other` is not special by itself; with two classes the
`Other` build emits 40 fewer data bytes and 80 fewer bss bytes.

**A semantic property cannot depend on the spelling of an identifier.** The
honest reading is that the defect is present in every one of these rows and only
the CRASH is conditional -- the walk either reaches unmapped memory or terminates
first, depending on layout. That is what reconciles this ticket's three recorded
observables (a wrong address with exit 0; a correct answer; a segfault) as ONE
defect rather than three, and it means **a row that prints the right answer is
not evidence the bug is absent**. Any fixture for this must assert the crash or
the address, never a value.

Deterministic: three recompiles of one source are byte-identical and five runs of
one binary agree, so this is source-shape sensitivity, not uninitialised memory
varying at run time.

**The `~5.5e6` in the summary is retired.** frankz-9c traced it to
`pyclsattr_bind` returning a sane bound-slot address of that magnitude; it is the
address of the right thing surfacing where a value belongs, not a corrupted
pointer. It is no longer the observable and should not be probed for.
