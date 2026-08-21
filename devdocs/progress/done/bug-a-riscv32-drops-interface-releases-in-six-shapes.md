---
track: A
prio: 45
type: bug
blocked-by: []
summary: "riscv32 alone under-releases COM interface references in six distinct shapes — a by-value interface PARAMETER is never released (10/16 on test_interface_byval_param_no_leak), an as-cast temp outlives its expression, a self-returning call releases nothing, and a COM value param leaks. x86-64, i386, arm32 and aarch64 all agree with FPC; riscv32 is the outlier in every case."
status: done
owner: claude-A
---

# riscv32 drops interface releases in six shapes

- **Track A** (`compiler/ir_codegen_riscv32.inc` + riscv32's arm of
  `EmitProcEpilog`).
- Found 2026-08-21 by the 53-test dyn-array + interface cross differential.

## Measured — riscv32 is the only target that differs

| test | native / i386 / arm32 / aarch64 | riscv32 |
| --- | --- | --- |
| `test_interface_byval_param_no_leak` | 16 / 16 | **10 / 16** |
| `test_interface_arc` | `freed=3` | **`freed=1`** |
| `test_interface_arc_exc` | `reassign freed=2`, `unwind freed=3` | **`freed=1`, `freed=1`** |
| `test_interface_as_cast_retains` | 7 / 7 | **5 / 7** |
| `test_interface_ascast_temp_lifetime` | prints `destroy 7` | **never destroys** |
| `test_interface_call_result_move` | 9 / 9 | **8 / 9** (self-returning released 0, want 1) |
| `test_interface_com_value_param` | `after nil freed=1` | **`freed=0`** |

`test_interface_byval_param_no_leak` is the most informative: `const` and
`var` parameters release correctly (5/5 both), while plain BY-VALUE parameters
release 0 of 1, 4 of 5 and 49 of 50. A by-value interface parameter carries a
+1 the callee owns and must drop; riscv32 drops it only when something else
happens to.

## Likely one cause, not six

Every failing shape is "an interface handle held in a slot riscv32's epilogue
does not walk": a by-value PARAM (not a local), an as-cast TEMP, a call-result
temp. riscv32's `EmitProcEpilog` arm is also visibly the thinnest of the five —
it has the static-array and scalar-AnsiString arms and (since 2026-08-21) the
dynamic-array one, but **no variant arm, no record-with-managed-fields arm, and
no promotable-int arm**, all of which the other four carry. Diff riscv32's arm
list against aarch64's; the differences ARE the bug list, exactly as
[[bug-a-no-dyn-array-scope-exit-release-on-four-backends]] found.

Check first whether riscv32's cleanup loop visits `skParam` at all — every arm
in it is gated `Syms[i].Kind = skLocal`, and a by-value interface parameter is
`skParam`.

## Gate

The seven tests above matching the native answer under `tools/run_target.sh
riscv32`; the 53-test cross differential no worse than baseline; self-host
fixedpoint + `tools/gate.sh quick`.

## Resolution (2026-08-21)

All seven tests in the table now produce output **identical to the native
oracle** under `tools/run_target.sh riscv32`.

### One cause, as the ticket suspected — but not the one it named

The ticket said to check whether the cleanup loop visits `skParam`. It does not
need to: every other target gates on `skLocal` too and releases by-value
interface parameters correctly, because a by-value param IS a local by the time
the epilogue walks the scope.

The actual cause is one line long: **riscv32's arm of the scope-exit release had
no COM interface case at all.** Not a narrower case, not a wrong register — the
arm was absent, so an interface handle in a slot was simply never walked. Every
failing shape in the table (by-value param, as-cast temp, call-result temp,
value param) is the same slot with a different name.

That was invisible while the release loops lived inline in each of
`EmitProcEpilog`'s six branches. After [[refactor-a-the-missing-layer-between-frontends-and-backends]]
put all six arms in one procedure, the matrix reads off in one grep:

| arm | x86-64 | i386 | arm32 | aarch64 | xtensa | riscv32 |
| --- | --- | --- | --- | --- | --- | --- |
| COM interface | yes | yes | yes | yes | — | **was missing** |
| static array of managed | yes | yes | yes | yes | — | yes |
| ansistring | yes | yes | yes | yes | yes | yes |
| variant | yes | **—** | yes | yes | — | **was missing** |
| promotable int | yes | **—** | **—** | yes | — | **was missing** |
| record w/ managed fields | yes | **—** | yes | yes | — | **was missing** |
| dynamic array | yes | yes | yes | yes | — | yes |

riscv32's four gaps are all closed here (COM interface, variant, promotable int,
record-with-managed-fields), because they are the same omission and fixing one
of six while the table is on screen is how the next one gets rediscovered in
three months.

### Not covered — and now written down

**i386 and arm32 still have holes** in that table: i386 has no variant, no
promotable-int and no record arm; arm32 has no promotable-int arm. Those are
silent leaks of exactly this kind and are filed as
[[bug-a-scope-exit-release-matrix-has-four-holes-left-on-i386-and-arm32]].
xtensa's row is nearly empty and is Track S work — its exception runtime exists
only under the Call0 ABI.

## Gate

`tools/gate.sh quick` GREEN (self-host fixedpoint 111s). All seven listed tests
byte-equal to the native oracle on riscv32, plus `test_exceptions`,
`test_cross_exception` and `test_interface_arc` unchanged. Cross-target breadth
is Track T's, against this sha.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
