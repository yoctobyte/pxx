---
slug: meta-a-second-paths-reimplement-the-first-paths-decisions
track: A
prio: 60
status: backlog
---

# One concept, two mechanisms, and only one carries the capability

**Four distinct subsystems, in one day (2026-08-17).** Filed as a structural
observation rather than four coincidences, because the repo's own rule says two is
a smell and three is a design flaw — and this is four.

| # | concept | path that works | path that doesn't |
| --- | --- | --- | --- |
| 1 | `@procvar` in Delphi mode | the value-context lowering | the `@` factor rebuilt the node kind and walked into the auto-call rule |
| 2 | `*args` unpacking at a call | free functions get `PyStarForwardCall`, a **run-time** arity dispatch that preserves defaults | methods route to a **compile-time** expansion that refuses any callee with defaults |
| 3 | shim attribute resolution | `.py` shims resolve `mod.attr` fine | Pascal-unit shims fail when the assignment TARGET shares the attribute's name |
| 4 | call-argument marshalling | the written-argument loop computes by-ref from the parameter (`ir.inc:9175`) | the default-fill path forty lines below passed a hardcoded `False` |

## The generalisation (Track A's, and it is the useful half)

> *Wherever a second path constructs call arguments, it reimplements the first
> path's decisions and drifts.*

Not "there are bugs in these four places". The claim is that a **second
construction path is a standing hazard**: it starts as a copy, the original grows
a capability, and the copy does not. Nothing fails at the edit site, because the
copy is still internally consistent.

## The tell, and it is what makes this actionable

**A local workaround sitting next to the general bug.** In case 4, a scalar default
is boxed into a temp whose address is passed regardless of the by-ref flag, and
`= None` **hand-builds a temp and LEAs it one branch over** — the same
address-taking, done manually. Somebody hit this, fixed their case locally, and
never saw the general one. The hand-rolled compensation is the fossil of an
earlier encounter.

So: **when you find a special-case branch doing manually what a nearby general
mechanism does automatically, the general mechanism is probably broken for
everything that does not have its own special case.** That is a grep-able shape,
not a philosophy.

Case 4 is also why the reported symptom was wrong: only a default whose hidden
global is *already* a variant reached the broken load, and a class is the one value
that lands there — so it presented as "a TYPE as a default segfaults" when the type
was incidental.

## What to do

Not a fix ticket. Proposed work, in order of cost:

1. **Enumerate the second paths.** Where does argument construction, name
   resolution, or node lowering have two entry points? Cases 2, 3 and 4 were all
   found by falling over them; none by looking.
2. **For each, ask what capability the first path has that the second lacks** —
   which is how all four were actually resolved: give the deficient path what the
   other has, rather than patch its symptom.
3. **Grep for hand-rolled compensations** next to general mechanisms, per the tell
   above.

`devdocs/dev/normalise-dont-special-case.md` is the principle; this is four days'
worth of evidence for it arriving in one night, and an argument that the audit is
worth doing deliberately rather than waiting to trip over number five.
