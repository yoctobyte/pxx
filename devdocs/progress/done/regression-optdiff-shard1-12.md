---
prio: 70
status: done
owner: frank1
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

## Root cause (frank1, 2026-08-26) — not a miscompile; the sweep started running a test it can never pass

Reproduced exactly, by mimicking the harness (same `d0`/`d2` output names, empty
environment):

```
r0=1 r2=1
--- o0 ---
(d0:1166619): Gtk-WARNING **: 10:39:01.745: cannot open display:
--- o2 ---
(d2:1166649): Gtk-WARNING **: 10:39:01.855: cannot open display:
```

Three independent sources of difference, none of them the compiler: the
**binary name** (optdiff writes `$TMP/d0`, `d2`, `d3` — so the -O level is IN
the compared text), the **PID**, and a **millisecond timestamp**. `test/t_rw.pas`
is a GTK3 GUI program; with no display gtk_init prints that line and exits 1.

**Why it went red now, with nothing in the GUI stack changed in the range.**
`74702c14d fix(T): a test job no longer inherits the human's desktop session`
is in the interval. plexus became the workstation on 2026-08-20, so until that
commit every job inherited `DISPLAY` — t_rw opened a real window, ran forever,
and was skipped as TIMEOUT-O0. The sweep had never compared it. Removing
`DISPLAY` was correct and is what made the job start reporting.

Same shape as the fpjson rung one ticket over: an unenrolled check asserts
nothing while looking like coverage, and enrolling it is what surfaces the
finding. `optdiff.skip` already carries `test_c_gtk_*` for exactly this class —
the glob was just too narrow to cover the one Pascal GUI test in the tree
(`grep -l gtk3 test/*` returns t_rw.pas and nothing else).

Fixed by listing it, with the reason, as the file's header requires.
- 2026-08-26 — resolved, commit 10cbe3470.
