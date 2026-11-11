---
track: B
prio: 50
type: bug
blocked-by: []
summary: "lib/rtl/interrupts.pas under -dPXX_NILPY stopped compiling: its implementation vars Dropped/Delivered share a name with the Python-surface functions dropped()/delivered(), and 5f11a77638 (a var may not redeclare any name of its own scope) rightly rejects that. The vars are now DroppedCount/DeliveredCount. Found by the same full tier: three $(TESTTMP) binary names written by two rows each, and two hardcoded /tmp paths in a nilpy test."
status: done
owner: unassigned
---

# interrupts.pas vs the new redeclaration check; TESTTMP name collisions

Found by a full tier on 2026-11-11 (raw-asm batches 22+23). None of it
came from that batch. Master's compiler fails the same way.

## interrupts.pas

`lib-test#191/#194/#195` failed:

    pascal26:292: error: duplicate identifier "Dropped": already declared in
    this scope as a routine   (lib/rtl/interrupts.pas)

The `{$ifdef PXX_NILPY}` Python surface declares `function dropped: Int64`
and `function delivered: Int64`. Pascal is case-insensitive, so the
implementation's counter vars `Dropped`/`Delivered` redeclare them. FPC
rejects that too. Since 5f11a77638 pxx does as well, so only the
-dPXX_NILPY builds broke. The counters are renamed to `DroppedCount` and
`DeliveredCount`. test_interrupts_pascal_no_pylib builds both ways again,
prints `event 7`, and keeps the size ratio (32 KB vs 507 KB).

## tools-devtest

- `t_no_new_binary_name_collision`: test_nilpy_lamobj26,
  test_nilpy_excstr26 and test_constshadow26 were each written by two
  rows. The newer rows now write test_nilpy_lamuser26,
  test_nilpy_excrtcls26 and test_constshadowouter26.
- `testmgr_hardcoded_tmp_devtest`:
  test_nilpy_a_write_to_a_file_never_closed_lands.py wrote to
  /tmp/test_nilpy_unclosed_{f,g}.txt. It now uses
  `TESTMGR_TMP or TESTTMP or /tmp`.

## test-core: c_incomplete_type_member_refused

The test wants exactly one OPAQUE diagnostic. Its trigger was
`struct dropped {...} __attribute__((aligned))`, but pxx now lays out a bare
`aligned` (16, as gcc does: `7 9 16` from both), so nothing went opaque and
the count was 0. The row now uses `aligned(__alignof__(long double))`, an
alignment given by an expression, which pxx still does not parse. The counts
are 3/3/1 again. Master's compiler fails the old row the same way.
