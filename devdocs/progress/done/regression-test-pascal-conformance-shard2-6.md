---
prio: 70
track: P
---

> **Track T by default: no lane could be inferred** from `tools/run_pascal_conformance.sh`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard2/6 red at f6303d410d78 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T09:10:29Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard2/6'` at f6303d410d783b2cbfad4ba500bf86bfa1a53b6d

## Range
> **The named sha `f6303d410d78` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f6303d410d78`, last good `90501813d990`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Of/local types inside generic routines)
SKIP tgenfunc15.pp — gap: generic array type templates + generic method overloads with array-of-T params
SKIP tgenfunc23.pp — gap: generic procedure overload on T vs array of T + inline specialize call
SKIP tgenfunc7.pp — gap: generic functions/methods imported from another unit and specialized
SKIP tinterface6.pp — gap: interface GUID/CORBA-UID usable as a typed constant (tguid/shortstring init)
SKIP tmoperator4.pp — gap: management operators across multiple record types
SKIP tobject6.pp — gap: `object` type with nested type/class var/const sections and class property
SKIP toperator3.pp — gap: unit-level `operator +` overload on records, mutually-used units
SKIP toperator78.pp — gap: global operator overloads on primitive/set types (**, ><, div, mod, and)
SKIP toperator89.pp — gap: overloading implicit assignment operator `:=` (global operator)
SKIP toperator94.pp — gap: objfpc `class operator :=` implicit conversion to shortstring types — the duplicate-conversion check (parser.inc ~1860) falsely collides distinct frozen-string result kinds; root is the same String[N] tk inconsistency (tyString vs tyFixedString vs tyShortString) that toperator93 exposed at the use site
SKIP tover3.pp — wontfix: dialect-pass — overload ambiguity — PXX deterministically ranks (picks longint for cardinal arg) by design; FPC-parity ambiguity errors belong to --strict-overload
SKIP tset2c.pp — gap: explicit enum ordinal values (dA:=17) + {$packset 1} packed-set semantics
SKIP tstring2.pp — gap: RTL `ExitCode` variable missing (needed by erroru unit); char-array to shortstring assign
test-pascal-conformance: 43 pass, 7 fail, 36 skip, 6 auto-gated (of 92)
test-pascal-conformance: FAILURES: tgenconstraint12.pp(accepted-invalid) tgenconstraint18.pp(accepted-invalid) tgenconstraint23.pp(accepted-invalid) tgenconstraint29.pp(accepted-invalid) tgenconstraint34.pp(accepted-invalid) tgenconstraint3.pp(accepted-invalid) tgenconstraint8.pp(accepted-invalid)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-30 (coordinator) — RETRACKED T → P, with a mechanism, and it points at TODAY'S `object` change

The ticket's own banner says Track T here is a **fallback, not a finding** —
`tools/run_pascal_conformance.sh` names no lane — and asks to be re-laned before
being worked. Re-laned to **P (Pascal frontend)**: the failures are generic
**constraint checking**, which is frontend semantics.

**All six shards report the same family**, from the report's excerpt:

```
test-pascal-conformance: FAILURES: tgenconstraint10.pp(accepted-invalid)
  tgenconstraint16.pp(accepted-invalid) tgenconstraint21.pp(accepted-invalid)
  tgenconstraint27.pp(accepted-invalid) tgenconstraint32.pp(accepted-invalid)
  tgenconstraint6.pp(accepted-invalid)
```

`accepted-invalid` = the test is `{ %FAIL }` and we no longer reject it.

**The mechanism, read out of the test sources rather than inferred from timing.**
`ugenconstraints.pas:65` declares `TTestObject1 = object`, and three of the six
specialize a template with it:

| test | specialization | constraint | must |
| --- | --- | --- | --- |
| `tgenconstraint6` | `TTest1<TTestObject1>` | `TTest1<T: class>` | FAIL |
| `tgenconstraint10` | `TTest3<TTestObject1>` | `TTest3<T: TTestClass>` | FAIL |
| `tgenconstraint16` | `TTest5<TTestObject1>` | `TTest5<T: IInterface>` | FAIL |

**`object` is exactly what changed on master today** —
`bug-p-object-value-types-standard-meaning`, landed `d23f52948` ~08:50Z: `object`
in type-declaration position stopped being a rooted class reference and became the
standard value type, lowered as an advanced record. **The shards went NEW-RED in
the 09:10Z full tier**, twenty minutes later, and no compiler file changed between
that tier and the next.

**This is a mechanism plus a coincidence in time, NOT a verified cause.** I have
not bisected and I have not run a single one of these tests. The disconfirming
measurement is one command and belongs to whoever takes this: run
`tgenconstraint6.pp` against `pinned` and against HEAD. If `pinned` rejects it and
HEAD accepts it, the link is established; if both accept it, the cause is older and
the timing is a coincidence.

**Note the shape if it IS the object change:** a *value* type should fail a `class`
constraint more obviously than a rooted class reference did, so "we stopped
rejecting it" suggests the constraint checker **lost the information it was
deciding on** rather than deciding differently — and a checker that falls through
to accept is one that may be accepting other invalid specializations silently.
That is the reason to price this above the compat table's *"we accept a form FPC
rejects → not a defect"* row: **these tests were GREEN this morning.** A gated
suite going from reject to accept is a regression whatever the philosophy says
about laxness, and the laxness ruling is about deliberate dialect choices, not
about a check that stopped firing.

**tgenconstraint21 (`TTest8<ITest1>`) and 27 (`TTest15<TTestClass4>`) do not
involve `object` at all**, so either the cause is broader than the `object` change
or there are two causes. Do not close the shards on the `object` link alone.


## SUPERSEDED 2026-08-30 — one defect, six views

Root cause found and filed as
[[bug-p-generic-type-constraints-are-parsed-and-discarded]] (P, p70). Closing
this shard ticket in its favour; do not work it separately.

**The mechanism.** `pasparser_generic.inc:1321` consumes a generic constraint
and never records it (`Next; { skip the constraint list }`), so no
specialization has ever been checked against one. Constraint checking is not
broken — it was never written.

**Why it appeared today.** `d23f52948` gave `object` its standard Pascal
meaning, which made `ugenconstraints.pas` parse. Before that, its line 65
(`TTestObject1 = object`) killed the whole shared unit, so every test importing
it failed to compile and reported green for a reason unconnected to what it
tests. Verified against both binaries: `pinned` rejects with
*"unexpected token in a unit interface section ... in: ugenconstraints.pas"*,
HEAD accepts.

**The count in these tickets is a shard artifact.** Six shards reported; the
real figure is **35 of 35** FAIL-marked tests that use that unit, wrongly
accepted on HEAD.

**Not a revert.** Reverting restores green by restoring a false green, and
re-breaks real Pascal source. These reds are the first accurate report this
suite has given about constraint checking.
