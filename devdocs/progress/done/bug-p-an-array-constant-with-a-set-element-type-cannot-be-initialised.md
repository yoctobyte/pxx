---
slug: bug-p-an-array-constant-with-a-set-element-type-cannot-be-initialised
title: "An array constant whose ELEMENT type is a set cannot be initialised at all"
track: P
prio: 80
type: bug
status: done
owner: "frankS"
found-by: frankuser
created: 2026-09-16
tags: [pascal, sets, array-constants, fpc-corpus, sibling-of-a-fixed-arm]
blocked-by: []
summary: "FIXED 2026-09-16 (14df2066b). `var a: array[0..0] of set of TF = ([]);` was refused with `too many array initializer elements` — ONE element, ONE slot, and the count never described the defect: `array[0..5]` with one element failed identically and the `near:` marker never moved off the first element. CORRECTION TO THE ORIGINAL SUMMARY: the set element type is NOT the whole cause — the CONST spelling of the identical declaration compiled fine all along. The discriminator is VAR vs CONST. ParseVarSection's array-element loop was never wired to the shared TryParseInitValForm helper, so a `[` reached an ordinal fallback that neither evaluates nor CONSUMES it; the loop spun on one token while the element counter advanced per spin. ParseConstSection's loop already called that helper. Cleared x86_64/cpuinfo.pas:281, which now reports only the remaining TDoubleRec wall."
---

# An array constant with a set element type cannot be initialised

- **Umbrella:** `umbrella-pxx-compiles-fpc-itself`
- **Sibling, already fixed:** [[bug-p-a-set-valued-record-field-cannot-be-written-in-a-record-constant]]

## Repro, 4 lines

```pascal
program p;
type TF = (fa, fb, fc);
var a: array[0..0] of set of TF = ([]);
begin WriteLn(1); end.
```

```
pascal26:3: error: too many array initializer elements
  near: of set of TF = ( >>> [ ] ,
```

**One element, one slot, and it still says "too many".** The diagnostic names a
count and the defect is not a count — widening the bound does not help:
`array[0..5] of set of TF = ([],[fa],[fa,fb])` fails identically. The `[` that
opens a set literal is being read as the start of a nested initializer.

## What is NOT the cause — measured, not assumed

| probe | result |
| --- | --- |
| `array[TC] of Integer = (10,20,30)` — enum bound, scalar element | **compiles**, prints 30 |
| `array[0..2] of set of TF = ([],[fa],[fa,fb])` — integer bound, set element | **refused** |
| `const r: TR = (s: [fa,fb]; n: 7)` — set in a RECORD constant | **compiles** |

So the enum index is innocent and so is the set type itself. It is specifically
**a set as an ARRAY CONSTANT's element**.

## Why it matters now

`x86_64/cpuinfo.pas:281`:

```pascal
cpu_capabilities : array[tcputype] of set of tcpuflags = (
  { cpu_none } [],
  { Athlon64 } cpu_x86_64_v1_flags, ... );
```

`tcputype` has **23** members and the initializer has **23** elements — FPC's
source is correct and we are wrong about it.

**132 of FPC's 207 compiler units report EXACTLY TWO errors and these are they**:
`unknown type: TDoubleRec` (cpuinfo.pas:36) and this one (cpuinfo.pas:281).
Nothing else, and the 20-error recovery cap is not in play — only one unit in the
whole corpus reaches it. **Both walls are in ONE FILE.**

**Do not read 132 as this ticket's yield.** A wall's population counts units
QUEUED behind it, not work (CLAUDE.md), and this umbrella has measured five
straight conversions at 0, 3 and 2 units. What IS new here is that these two are
the units' *complete* reported failure set rather than their first — so clearing
BOTH is the first proposal this umbrella has had with evidence behind it rather
than a queue position. A third wall in the same file is still the most likely
outcome and should be expected, not treated as a surprise.

## Where to start

`138604b5e` fixed the record arm. Read what it did and look for the array arm
beside it — `normalise-dont-special-case.md`: fixed one arm of a double case,
grep for the sibling before closing. That is exactly what happened here, and
this ticket exists because nobody did.

---

## RESOLVED 2026-09-16 (frankS, Track P) — `14df2066b`

**One correction to the diagnosis, and it changes where the fix goes.** The
ticket says *"the SET ELEMENT TYPE is the whole cause"*. It is not: the **const**
spelling of the identical declaration compiled fine the whole time. Nine cells,
measured before touching anything:

| | var | const |
| --- | --- | --- |
| `array[0..1] of set of TF` | **REFUSED** | OK |
| `array[TF] of set of TF` | **REFUSED** | OK |
| `array[0..1] of TS` (named set type) | **REFUSED** | — |
| `array[0..1] of Integer` | OK | OK |
| plain `set of TF` | OK | OK |

So neither the set type nor the enum bound is implicated. **The discriminator is
the storage class**, and the sibling is not the record-field bug this ticket
names — it is the **const array arm**, which was closed by routing that loop
through the shared `TryParseInitValForm` helper.

**Mechanism.** `ParseVarSection`'s array-element loop was never wired to that
helper, so every non-ordinal element form it carries — a set literal, a PChar,
an `@X` — fell through to the ordinal fallback, which cannot evaluate a `[`
**and does not consume it either**. The loop spun on one token while
`Inc(initElem)` counted a slot per spin, until the length check tripped. That is
why the count was never the defect and why the `near:` marker never moved: a
size complaint about a correct size, with `TokPos` standing still.

`ParseConstSection`'s loop carries a comment recording this exact paragraph
**four times over** — string, PChar, set, `@X` — and concluding it had to be a
shared helper rather than a fifth hand-written arm. It was right. The fix is one
`else if` calling the same helper, not a second copy of the rule.

**Placement is deliberate:** after the existing string and class-reference arms,
not before. Those key on the *destination* type to resolve a genuinely ambiguous
token (a one-char literal into a `tyChar` element is an ordinal, not a string),
so hoisting the helper above them would re-open bugs they were written to close.
Verified — char and string var array initializers produce byte-identical
binaries before and after.

**Test:** `test/test_var_array_of_sets.pas`, the var twin of
`test_const_array_of_sets`. Asserts VALUES via a 3-bit code (a wrong 32-byte
mask compiles fine and would pass a membership flag), with the empty set first,
an enum bound, a routine-local array (`LocalInit` rather than `PendingInit`),
and a store after init — the row a const array cannot have.

**Control:** the fixture is REFUSED at the expected line by pin v410 *and* by the
pre-change binary; green after. Self-host fixedpoint converged, `gate.sh quick`
GREEN.

**Corpus effect, stated narrowly.** `x86_64/cpuinfo.pas` now reports **one**
error instead of two — only `feature-b-rtl-has-no-tdoublerec` remains. That is a
claim about *that unit's diagnostics*, not about the 132 units queued behind it:
clearing a wall delivers its population to whatever is next in **their own**
source. Measured separately — with both walls stubbed, `cpuinfo.pas` itself
compiles clean, so there is **no third wall in that file**, which was the
prediction on record. The per-unit consequence is in the umbrella.

**Slug kept deliberately** — it says "array constant" where the defect is a
`var`, but a slug is a citation and renaming it would break the links. The
summary carries the correction.

## Log
- 2026-09-16 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
