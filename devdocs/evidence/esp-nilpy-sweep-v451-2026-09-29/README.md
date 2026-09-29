# Nil Python corpus on the ESP32-C3 and ESP32-S3, v451, 2026-09-29

Board record of frankB's ESP sweep: every `test/test_nilpy_*.npy` row built for
the ESP32-C3 (riscv32) and the ESP32-S3 (xtensa, windowed ABI), run under
Espressif QEMU, and compared with the same row's x86-64 host output.
Differences were then checked on real boards. `rows.tsv` lists every row that
differs or does not build, with its class and owner.

## Provenance

- Compiler: pin v451, sha256 `d9b7226769cc`, tree `c1e695a05b`. Where a row
  says FIXED, the fix was checked with a compiler built at origin `5e8f30bd4d`
  (sha256 `315cf16ef386`).
- ESP-IDF v6.0.1; Espressif QEMU `esp_develop_9.2.2_20250817`. Rows ran in the
  `nilpy-station-c3` / `nilpy-station-s3` projects at a 16 KiB main stack,
  the value before `93e6adbf5f`.
- Boards: an ESP32-C3 on its built-in USB-JTAG serial port and an ESP32-S3
  behind a CH343 UART bridge.
- How rows run: each row is wrapped as an imported module and batched, and
  any batch difference is re-run alone. Every row that still differed, and
  every row that failed to build only on the ESP, was re-run on v451 itself.
  The rows that matched in the first pass ran on earlier compilers: v448–v450
  work trees `0ded1e5d04c8`, then `8d5d0f2653f0` (C3 from row 836, S3 from
  row 202).
- The runner and the raw outputs are in frankB's work directory, not in
  the repository.

## Counts on v451

943 rows ran. 77 more were excluded before the sweep because they need a host
facility the ESP does not have: 36 host modules, 24 files, 15 argv/stdin/host
sys, 2 C imports.

| | rows | built | do not build (of those, also fail on the host) | same as host | differ |
| --- | --- | --- | --- | --- | --- |
| ESP32-C3 | 943 | 851 | 92 (75) | 821 | 30 |
| ESP32-S3 | 943 | 848 | 95 (75) | 816 | 32 |

The 75 rows that fail on the host too are negative tests or host-only rows.
The per-row breakdown of everything else is in `rows.tsv`.

## Differences, by cause

**Compiler bugs, routed; not ESP-specific.** The same wrapped row fails on
x86-64 too, or it fails on every backend except x86-64:

| rows | cause | owner |
| --- | --- | --- |
| `user_class_shadows_builtin`, `class_attr_shared_slot_via_call_result` | inside an imported module, a user class named `Counter` resolves to pylib's Counter dict | frankh-95 |
| `user_def_shadows_builtin` | in an imported module, a user `def len` called on a for-loop variable segfaults | frankh-95 |
| `str_param` | `Length()` in an imported module returns 6 for `"ab"` | frankh-95 |
| `keyword_call_tuple_on_a_skipped_default` | wrong on every backend except x86-64 | frankz-e5 |
| `pyeval_host_kwargs_bind_by_name`, `pyeval_host_mixed_params` | pyeval host items | frankz-e5 |

**Fixed since v451, confirmed on silicon:**

| rows | cause | fix |
| --- | --- | --- |
| `wide_call_through_a_callable_value` | main-task stack overflow at 16 KiB: an 8 KiB module-body frame plus about 10 KiB of interpreted-lambda recursion. S3: LoadProhibited. C3: stack protection fault on the board only; QEMU hid it | `93e6adbf5f` (S3 32 KiB, C3 24 KiB) |
| S3 only, do not build: `a_dataclass_ctor_takes_as_many_fields_as_a_proc`, `a_method_takes_more_than_sixteen_parameters`, `escaping_closure_many_captures` | a def with more than 16 parameters: "parameter frame offset out of range" | `5e8f30bd4d` |

**By design, do not route:** `catchable_runtime_errors`,
`float_overflow_raises`, `math_domain_errors`, `pow_domain`,
`print_arg_eval_order`, `pow_matches_cpython` and
`math_frexp_isqrt_isfinite_are_exact` follow the ESP math rule. `x / 0`,
`x % 0`, overflow and domain errors give inf, nan or 0 with no exception;
subnormals flush to zero; `pow` is within about 1e-13.

**Sweep-harness artefacts** (the row is correct outside the wrapper):
- `atexit_io`, `from_import_as_alias`, `module_identity`,
  `module_member_as_a_value`, `py_module_import`: the wrapper cuts off output
  after the batch end, or reorders module-init output.
- `a_builtin_over_a_variant_list_releases_its_copy`: the host oracle itself
  timed out.

**QEMU artefacts** (MATCH on the C3 board): `object_in_variant_slot_survives_churn`,
`variant_str_boxing`, `variant_borrow_two_slots` (S3 in QEMU).

## Size and speed ceilings

These are not wrong values. Output is correct up to the point where the board
runs out of heap or of time.

| row | chips | what runs out |
| --- | --- | --- |
| `collections_deque` | C3, S3 | heap: a 20,000-element deque (board) |
| `str_repeat_linear` | C3, S3 | heap: `"x" * 80000` (board) |
| `re_findall_past_the_old_4096_cap` | C3, S3 | heap: the k=4096 case (board) |
| `promo_local_zero_init` | C3, S3 | heap: 3000 strings of 40 chars; the C3 board runs out at about 1250 (see below) |
| `the_struct_module` | C3, S3 | heap: the 12,000-element pack (QEMU only) |
| `class_field_no_container_no_leak` | C3, S3 | time: 200,000 copies of a 2000-char string; flat memory, over 600 s on the board |
| `exception_no_leak` | C3, S3 | time: 640,000 raise/except; 4.4 s even on x86-64 |
| `float_repr_roundtrip` | C3 | time: MATCH on the board, slower than the QEMU window |
| `managed_local_in_unwound_frame` | S3 | time: correct on the board, with task-watchdog messages in the output |

Heap on the C3 station at 16 KiB main stack: `free_heap` 260,556 B,
largest free block 126,976 B. At 24 KiB, after `93e6adbf5f`: 249,308 and
114,688. A list holds about 4,000 ints; `list.sort()` needs about the list's
size again (`test/esp_board_list_sort_ceiling.npy`).

A string built as `"x" * n` costs 2n + 68 bytes of heap on v451, against
n + 44 for the same string built by concatenation. `PXXStrSetLen` doubles
the first sizing of a Nil Python empty string, which is not nil. The fix is
routed to franks-a3.

## Interrupt-watchdog panics under QEMU are QEMU-only

frankd-90 saw a 100,000-iteration Nil Python loop with the `interrupts` module
end in "Interrupt wdt timeout on CPU0" on C3 QEMU (v451). The program is
`~/frankD-wt/tmp/espdiv/irq.npy`; the 1000-iteration twin is `irq2.npy`.

- On the C3 board it never trips the interrupt watchdog, on v451 or at
  `315cf16ef386`. At tip it completes: both handlers run in the drain,
  `delivered 2`, `log [1, 2]`, `irq probe done`. On v451 the loop only
  starves the task watchdog and takes more than 90 s, because `x` passes
  2^31 and each add takes the big-int path that `36c83f225a` sped up.
  `irq2.npy` gives the same correct output on v451.
- The QEMU panic PC `0x40384af2` is `vPortYield` (FreeRTOS `port.c:653`)
  spinning in `crosscore_int_ll_get_state`. Its return address `0x40384b84`
  is `SysTickIsrHandler` (`port_systick.c:136`); both were resolved against
  `hello-c3` builds from the same IDF. No PXX code is on that frame. It is
  QEMU's emulation of the cross-core yield interrupt.
