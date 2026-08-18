---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-pascal-conformance#shard5/6 red at 61e2448bac6d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-18T04:23:41Z
- **Test source:** tools/run_pascal_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-pascal-conformance#shard5/6'` at 61e2448bac6d3f61657fb54a746d3e33d2ad96fc

## Range
bad `61e2448bac6d`, last good `e0f6748717e6`, 12 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL tset3.pp — compile error:
pascal26:77: error: invalid optional IR node reference in block first
(tail)
cf); not a bug
SKIP tgeneric26.pp — gap: accepts-invalid — type parameter in a variant part must be rejected (substitution model has no pre-specialization check)
SKIP tgeneric48.pp — gap: mixed generic overloads by arity (class/record/interface/procvar/array)
SKIP tgeneric59.pp — gap: same generic name with different arity (TTest<T> vs TTest<T,S>) in delphi mode
SKIP tgeneric64.pp — gap: generic record with nested class type
SKIP tgeneric6.pp — gap: objfpc generic syntax + nested record/pointer types inside a generic class
SKIP tgeneric91.pp — gap: Self in class procedure of a generic class specialized cross-unit
SKIP tgeneric97.pp — wontfix: expects FPC's internal specialized ClassName 'ttest<system.longint>'
SKIP tgenfunc12.pp — gap: generic methods with class/interface constraints and generic global functions
SKIP tgenfunc4.pp — gap: delphi-mode generic class function with inline type args
SKIP tmoperator1.pp — gap: management operators Initialize/Finalize (advancedrecords)
SKIP tmoperator7.pp — gap: management operators inside object/dynarray of records + class var
SKIP toperator6.pp — gap: `operator :=` implicit-conversion overload + qword/int64 overload selection
SKIP toperator91.pp — gap: class operators Explicit/Implicit overloaded on ShortString[N] result types
SKIP tprocvar2.pp — gap: typed const procvar initialized with bare proc name (TP mode), procvar via move()
FAIL tset3.pp — compile error:
    pascal26:77: error: invalid optional IR node reference in block first
      near:  writeln  ok   >>> end  unit 
SKIP tsetsize.pp — wontfix: asserts FPC's exact set-size/packing layout (SizeOf(set of subrange))
SKIP tstring10.pp — gap: punicodechar/pwidechar value casts + unicodestring/widestring conversions (Flush/Output landed)
SKIP tstring5.pp — gap: RTL `ExitCode` variable missing (needed by testsuite erroru unit); ansistring compares
test-pascal-conformance: 50 pass, 1 fail, 33 skip, 7 auto-gated (of 91)
test-pascal-conformance: FAILURES: tset3.pp(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
