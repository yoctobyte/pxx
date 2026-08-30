---
prio: 35
track: A
---

# chore(A): adopt AllocRecVar at the 20 remaining `AllocVar(…, tyRecord)` sites

`AllocVar` sizes a `tyRecord` symbol from **`LastTypeRecId`**, a global
side-channel left behind by whatever declaration the parser last saw. Every
caller that wants a record temp of a *known* type therefore has to set that
global first and put it back afterwards, by hand, at the right moment. Five
sites in `ir.inc` did; **one did not**, and the result was a 240-byte record
allocated 8 bytes (`RecSize(REC_NONE)` = 8) and then zeroed with 240 — an
out-of-bounds BSS write that was invisible for as long as the page round-up
slack absorbed it, and became a hard SIGSEGV the day `75d2ba662` page-aligned
the image. Diagnosis: `regression-test-asm-compiler-2` (frankA). Fix:
`AllocRecVar(name, recId)` in `symtab.inc`, which makes "forgot to set
`LastTypeRecId`" unrepresentable, and the five `ir.inc` sites converted.

**This ticket is the rest of the conversion.** Twenty `AllocVar(…, tyRecord)`
calls remain, and they are in files this lane does not own:

| file | sites |
| --- | --- |
| `pasparser_expr.inc` | 694, 7160 |
| `pasparser_stmt.inc` | 4996 |
| `pyparser.inc` | 48015 |
| `cparser.inc` | 2968, 8712, 10775 |
| `rparser.inc` | 1516, 1583, 2383, 2497, 3382, 3421, 3433, 3450 |
| `zparser.inc` | 1015, 1033, 1100, 1153, 1184 |

Each needs the same reading `ir.inc` got, one at a time: **does this site
already know the record id?** If it does, it should pass it (and any
save/restore of `LastTypeRecId` around it deletes). If it genuinely means "the
declaration the parser just parsed", it is correct as it stands and should get
a one-line comment saying so, because that is the case a reader cannot tell
from the call. Do not convert mechanically — the point is to remove the
side-channel where it is not wanted, not to rename every call.

## The stronger guard, and why it is not built yet

`AllocVar(name, tyRecord)` with `LastTypeRecId = REC_NONE` is, as far as
anything measured shows, always a defect: it allocates 8 bytes for a record.
Measured on an instrumented build at `32ef5081fe89` — a `writeln(StdErr)` on
exactly that condition — the count is **0** for `compiler/compiler.pas`
(37k lines, every frontend), `lib/rtl/system.pas`, `test_asmcore_x64`,
`test_interfaces`, `test_records`, `test_generics`, `test_classes`,
`c_builtin_bits.c`, `lib_codecs.npy` and `lib_mimic_collections_abc.npy`. So
turning the condition into a hard `Error` would fire nowhere today and would
have caught this bug at the moment it was written.

It is not in this session's commit because the blast radius lands in R and Z,
whose suites this lane cannot run, and a fatal that fires in someone else's
frontend on a Saturday is a worse trade than the bug it prevents. Turn it on
**with** the conversion above, once each of the twenty sites has been read: at
that point a `REC_NONE` record allocation is not merely unmeasured, it is
accounted for.

## Gate
`make compiler/pascal26` (self-host fixedpoint) + the owning frontend's tests
for whichever files a given commit touches. Land per-file, not in one sweep.
