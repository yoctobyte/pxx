---
prio: 70
track: P
---

> **Track T by default: no lane could be inferred** from `tools/run_pascal_conformance.sh`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard3/6 red at f6303d410d78 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T09:10:29Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard3/6'` at f6303d410d783b2cbfad4ba500bf86bfa1a53b6d

## Range
> **The named sha `f6303d410d78` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f6303d410d78`, last good `90501813d990`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
e IGenericIntf<T>)` parent-list specialize (interface templates capture now)
SKIP tgeneric84.pp — gap: accepts-invalid — invalid generic record body accepted (pre-specialization checking)
SKIP tgeneric8.pp — gap: objfpc generic syntax + inline methods over nested generic types
SKIP tgeneric95.pp — gap: specialize inside a generic routine signature (`expected name` at line 16)
SKIP tgenfunc10.pp — gap: inline `specialize` expression inside generic function body
SKIP tgenfunc2.pp — gap: generic (parameterized) standalone functions in mode delphi
SKIP tgenfunc8.pp — gap: generic FUNCTION with <T> in result/args (scalar operators land; parse dies at the generic func decl)
SKIP tmoperator10.pp — wontfix: probes TypInfo GetTypeData ElType/ElType2 RTTI layout of dyn array
SKIP tmoperator5.pp — gap: management operators Initialize/Finalize invocation order
SKIP tobject1.pp — gap: object constructor `fail`, erroru/ExitCode RTL support
SKIP tobject7.pp — gap: `object` with private nested type, typed const and static class property
SKIP toperator2.pp — gap: unit-level `operator +` overload on records (global operator overloading)
SKIP tover4.pp — gap: 80-bit extended/cextended float type and overload resolution across single/double/extended
SKIP tpropdef.pp — wontfix: depends on FPC Classes/TComponent published-property RTTI streaming (stored/nodefault)
SKIP trange5.pp — gap: `with` over a record typecast (int64rec(q)) plus 64-bit {$R+} range checks
SKIP tset2d.pp — gap: explicit enum ordinal values (dA:=17) + {$packset 2} packed-set semantics
SKIP tstring3.pp — gap: typed-const array of short/ansistring initialized from char & resourcestring consts
test-pascal-conformance: 51 pass, 6 fail, 29 skip, 6 auto-gated (of 92)
test-pascal-conformance: FAILURES: tgenconstraint13.pp(accepted-invalid) tgenconstraint19.pp(accepted-invalid) tgenconstraint24.pp(accepted-invalid) tgenconstraint2.pp(accepted-invalid) tgenconstraint35.pp(accepted-invalid) tgenconstraint9.pp(accepted-invalid)

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
