---
track: C
prio: 55
type: bug
blocked-by: []
summary: "A C function DEFINITION whose name matches a Pascal intrinsic (`sqrt` `exp` `ln` `sin` `cos` `arctan`) binds to the Pascal proc entry via case-insensitive FindProc and overwrites its BodyAddr. The Pascal implementation then becomes unreachable by ANY spelling — bare `Sqrt`, `math.Sqrt` and `cmath.sqrt` all return the C body — so a C file silently replaces the RTL's math for the whole program. This is what the ten `__crtl_*` prefixes in lib/crtl exist to dodge."
status: done
owner: frank2-C
---

# A C definition of an intrinsic name overwrites the Pascal routine, unreachably

Found 2026-08-16 while measuring
[[feature-a-own-language-first-symbol-resolution]] at HEAD. Filed separately
because it is a **silent wrong value from the RTL**, not a resolution-precedence
design question — the compat escape rule in `CLAUDE.md` promotes exactly this to
a `bug-` ticket in the owning lane.

## The boundary, measured

Every row is one four-line program plus a C file whose function returns a
sentinel. `cmath` is `uses './x.c' as cmath`.

| Pascal side | bare call | `unit.Name` | `cmath.name` |
| --- | --- | --- | --- |
| a user unit's `Cube` vs C `cube` | **27 — Pascal** | 27 | 999 |
| math's `Tanh` vs C `tanh` | **0.7616 — Pascal** | 0.7616 | 55.0 |
| math's `Sqrt` vs C `sqrt` | **42 — C** | **42 — C** | `undefined variable (sqrt)` |
| math's `Exp` vs C `exp` | **42 — C** | **42 — C** | `undefined variable (exp)` |

Rows 1-2 are correct in all three columns, and row 1 is **order-independent**
(`uses pcube, './x.c'`, `uses './x.c', pcube`, with and without `as`) — so
cross-language resolution is already own-language-first for ordinary units, and
the alias escape already works. Rows 3-4 are the defect, and it is confined to
the six names the auto-pull scan treats as intrinsics (`parser.inc:34716`):
`sqrt`, `exp`, `ln`, `sin`, `cos`, `arctan`.

`math.pas` itself is NOT damaged — `SqrtSoft(16.0)` still returns 4.0 in the same
program where `Sqrt(16.0)` returns 42.0. Only the `Sqrt` proc ENTRY is hijacked,
which is why both the bare and the `math.`-qualified spelling follow it.

## Mechanism

`cparser.inc:9401`, on a C function with a BODY:

```pascal
procIdx := FindProc(name);          { spans C and Pascal, case-insensitively }
...
Procs[procIdx].BodyAddr := CodeLen; { :9558 — overwrites the Pascal routine }
```

`FindProc` is case-insensitive and spans namespaces, so C's `sqrt` lands on
Pascal's `Sqrt`. Same arity and both sides float, so neither guard fires — the
arity rung (`CCrossNamespaceArityMismatch`) and the float-class rung both pass —
and the C body is installed into the Pascal entry.

The cross-namespace bind itself is **deliberate and must stay**: the comment at
`:9448` records that lua's `<math.h>` `sqrt`/`sin`/`cos` resolve to the RTL math
routines that way. But that is the DECLARATION case (a prototype, no body). A
definition is a different claim: it says *this translation unit provides the
function*, and it should get its own proc in its own unit rather than
overwriting someone else's.

Rows 1-2 escape only because their Pascal counterpart is reached through a
path that does not collide this way (row 2's `Tanh` has no intrinsic entry to
land on), not because anything checks the language.

## Why this is the blocker for the de-prefix acceptance test

`lib/crtl/src/math.c` deliberately misnames ten functions — `__crtl_exp`,
`__crtl_log2`, `__crtl_log10`, `__crtl_sin`, `__crtl_cos`, `__crtl_tan`,
`__crtl_sinh`, `__crtl_cosh`, `__crtl_tanh`, `__crtl_hypot` — with the reason in
the source: *"that name collides case-insensitively with Pascal Exp (two
definitions -> silently broken call binding)"*.

Those `#define`s are the workaround for THIS bug. So
[[feature-a-own-language-first-symbol-resolution]]'s acceptance test (de-prefix
the ten, delete the `#define`s in crtl's `math.h`) cannot pass until a C
definition stops overwriting the Pascal entry. That ticket's own measurement
(2026-08-14) found the C -> Pascal direction closed and concluded the prefixes
were "probably vestigial" — that holds for a C program compiled alone, and this
row is the case it did not cover: a MIXED program, where the Pascal side is
still live.

## Suggested shape (not prescriptive — Track C owns the file)

Split the definition case from the declaration case at `cparser.inc:9401`: when
the C function has a body, do not accept a `FindProc` hit that landed on a proc
of another language / another unit — register a fresh proc in the C unit
instead. That is also what makes `cmath.sqrt` resolve, since the qualified
lookup (`MatchProcCallInUnit`) needs a proc whose `ProcUnitIdx` IS the C unit,
and today none exists.

There is no `ProcLang` parallel array yet;
[[feature-a-own-language-first-symbol-resolution]] notes one is needed and that
`ProcCdecl` is the wrong instrument for it (it is a calling-convention decorator
and a Pascal routine may carry it). If this fix needs the language tag, that
array is a Track A change — file it rather than deriving the language from
`ProcCdecl`.

## Repro

```pascal
{ cm.c:  double sqrt(double x) { return 42.0; } }
program p; uses math, './cm.c' as cmath;
begin
  WriteLn(Sqrt(16.0):0:4);        { 42.0000 — want 4.0000 }
  WriteLn(math.Sqrt(16.0):0:4);   { 42.0000 — want 4.0000 }
  WriteLn(SqrtSoft(16.0):0:4);    {  4.0000 — math.pas is intact }
end.
```

## Gate

C tests green + `make test` + self-host byte-identical. Add a positive test for
all four rows of the table above (the two correct ones are the must-not-regress
controls — they are what proves the fix did not disturb the deliberate
declaration-side cross-bind that lua depends on).

---

## 2026-08-19 — this is now a PREREQUISITE, and the ":9448 must stay" quote is not settled

Design conversation with the user filed as
[[feature-c-import-a-pascal-unit-under-a-mangled-name]] (C, p50), which **blocks on this
ticket**. Nothing in that design changes what to do here — the fix below is correct under
every branch of it — but two notes for whoever takes it.

### The fix is the declaration/definition split, and it is not in dispute

`cparser.inc:9401` calls `FindProc(name)` for a C function **with a body** and `:9558`
overwrites `BodyAddr` on whatever it finds. A **declaration** binding cross-namespace is a
deliberate, documented behaviour. A **definition** is a different claim — *this translation
unit provides the function* — and it should get its own proc in its own unit rather than
seizing someone else's entry. Fix that asymmetry; the ticket's own Mechanism section says
the same.

### But do NOT treat `:9448`'s justification as load-bearing without checking

The comment defends the cross-namespace bind with: *"lua's `<math.h>` `sqrt`/`exp`/`sin`/…
resolve to the RTL math routines."* That may be **stale**. Measured 2026-08-19:
`lib/crtl/src/math.c` DEFINES `exp` (:282), `log` (:341), `sin` (:644), `cos` (:656),
`atan` (:724) and `sqrt` (:965) as correctly-rounded C, and `CPullCrtlForPrototypes` pulls
that module when a C file declares those prototypes. So C may already have its own libm and
the bind may be legacy from before it did.

**This is flagged, not concluded.** Three stale "must stay" justifications turned up in one
day (this, `stdarg.h`'s macro-reset story, `feature-mimic-fpc`'s scoped manifest), so the
prior on a confident old comment is lower than it looks — but the way to settle it is the
experiment written into the feature ticket (delete the declaration bind, build lua / tcc /
quickjs / zlib), **not** to widen this fix on a hunch. Keep this ticket to the
definition case.

### Standing context

Still the single unmet blocker on `feature-a-own-language-first-symbol-resolution`, which
sits in `unfinished/` **and** carries a `blocked-by` — two independent switches, either of
which alone hides it from `ready`/`next`. When this lands, clear both.


---

## FIXED 2026-08-19 (Track C, frank2-C)

**The fix is the declaration/definition split the ticket specifies, with one
change of instrument: the discriminator is exact CASE, not the unit.**

`cparser.inc`, at the `FindProc(name)` site — a new rung 0, ahead of the arity
and float-class rungs. When the hit's stored name differs from the C spelling
(`Procs[procIdx].Name <> name`, i.e. a differently-cased twin) the parser peeks
ahead for `{` vs `;`, and **only if a body follows** drops the bind so a fresh
proc registers in the C unit. The peek saves and rewinds `TokPos` the way the
rest of the file does; the real declaration/definition scan below is untouched.

### Why case rather than "another unit / another language"

The ticket suggested refusing a hit that landed on a proc of another unit, and
noted that a `ProcLang` array does not exist. Case turns out to be both
sufficient and *safer*, and it is this file's own precedent — the
`forceSystemExternal` loop already compares `Procs[i].Name = name` and records
the reason: it "excludes differently-cased Pascal twins (Sqrt vs sqrt)".

The unit test would have been **wrong**. `lib/crtl` deliberately redefines
Pascal builtins it spells *identically* — malloc, memcpy, strtod and dozens
more live in `compiler/builtin/*.pas` **and** `lib/crtl/src/*.c`. Those
overwrites are load-bearing: if a C `malloc` and a Pascal `malloc` became two
procs, a program would have two allocators, and memory obtained from one and
released by the other is heap corruption. A same-spelling redefinition is a
deliberate override; only a twin Pascal spells differently is a hijack. So no
`ProcLang` array is needed and no Track A ticket falls out of this.

**The `:9448` "lua needs it" comment was left alone**, as the 2026-08-19 note
directs: this fix touches only the definition case, and the declaration bind is
verified below to still work.

### Measured — the boundary table, before and after

Compiled and run against a fixedpoint build at this change:

| | before | after | want |
| --- | --- | --- | --- |
| `Sqrt(16.0)` | 42.0000 | **4.0000** | 4.0000 |
| `math.Sqrt(16.0)` | 42.0000 | **4.0000** | 4.0000 |
| `Exp(0.0)` | 42.0000 | **1.0000** | 1.0000 |
| `cmath.sqrt(16.0)` | `undefined variable (sqrt)` | **42.0000** | C's, by name |
| `SqrtSoft(16.0)` | 4.0000 | 4.0000 | unchanged |

The fourth row is the one that shows the fix is the *right* one rather than
merely a block: the C definition is now reachable through the alias, because a
proc finally belongs to the C unit.

### Controls — nothing else moved

- **Rows 1-2 of the table** (a user unit's `Cube` vs C `cube`; math's `Tanh` vs
  C `tanh`): 27 / 27 / 999 and 0.7616 / 55.0000, exactly as before.
- **The declaration-side cross-bind lua depends on**: a C file that *declares*
  `double sqrt(double);` and calls it still reaches the RTL — `cd.use(16.0)`
  returns 4.0000. This is the behaviour the ticket was careful to preserve.
- **A plain C program** using `malloc` / `strcpy` / `strlen` / `sqrt` / `exp`
  through the real headers prints `hi 4.0000 1.0000 2` — **byte-identical to
  the same program built with gcc**, so crtl's same-spelling overrides are
  undisturbed.

### Test

`test/test_c_def_hijack.pas` + `test/c_def_hijack.c`, wired into the Makefile
next to `test_c_cross_ns_arity` (enumerated, not globbed). It asserts all four
boundary rows plus the two controls in one program, with sentinel return values
(42/43/55/999) no real implementation would produce. Verified by running the
recipe's exact comparison, not just the program.

### Gate

`make compiler/pascal26` — converged after 1 round, byte-identical.
`tools/gate.sh quick` — **GREEN** (testmgr quick + FPC seed canary).
The full C corpus (lua, zlib, quickjs, tcc) is Track T's sweep against this
sha; the corpus shape most at risk — same-spelling crtl overrides — is covered
by the gcc-oracle control above.

### Follow-on

`feature-a-own-language-first-symbol-resolution` names this as its single unmet
blocker and carries **two** independent switches hiding it — a `blocked-by`
edge *and* sitting in `unfinished/`. Both need clearing now that this has
landed; it needs the A slot, so it is flagged rather than done here.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
