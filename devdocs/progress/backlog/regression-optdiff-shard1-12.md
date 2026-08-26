---
prio: 70
---

> **origin/dev has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard1/12 red at fffd29ea840d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-26T08:20:39Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard1/12'` at fffd29ea840d126f428af41a670b92779f89f4c3

## Range
> **The named sha `fffd29ea840d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `fffd29ea840d`, last good `8f403875d51a`, 63 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
OPT DIFF -O2: test/t_rw.pas (rc 1 vs 1)
OPT DIFF -O3: test/t_rw.pas (rc 1 vs 1)
optdiff skip SKIPLIST: test_rtti_emit.pas
optdiff skip TIMEOUT-O0: cfloat_lea_ptr_b195.c test_c_argspill.pas test_exception_unit_unhandled.pas
optdiff skip BUILD-FAIL: c_vla_const_fail.c crtl_tiny_regex_match.c except_b322_thrower.pas lazycasing_lib.c spill_lib.c test_assign_incompatible_types_fail.pas test_c_cross_ns_arity_fail.pas test_directive_if_float.pas test_enum_identity_fail.pas test_enum_pointer_compare_fail.pas test_exitcode_halt_arg.pas test_parallel_writeln_atomic.pas test_pascal_duplicate_class_fail.pas
optdiff shard 1/12: pass=132 skip=17 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
