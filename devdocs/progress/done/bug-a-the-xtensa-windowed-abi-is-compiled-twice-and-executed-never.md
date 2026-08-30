---
slug: bug-a-the-xtensa-windowed-abi-is-compiled-twice-and-executed-never
track: A+S
prio: 60
type: bug
blocked-by: []
status: done
found: 2026-08-30
found-by: frankS
owner: frankS
summary: "test-xtensa has 107 executed rows and every one is Call0. The windowed ABI appears twice in the whole Makefile and BOTH rows are compile-only — one greps a .o header, the other prints 'lowers ok'. Nothing has ever run a windowed program and compared its output, which is why 41 windowed programs SIGBUS'd for an unknown length of time and were fixed by accident."
---

# The xtensa windowed ABI is compiled twice and executed never

## The gap, counted

| | |
| --- | --- |
| executed rows in `test-xtensa` | **107**, all Call0 |
| `--xtensa-abi=windowed` anywhere in the Makefile | **2** |
| windowed programs ever RUN and compared | **0** |

Both windowed rows assert that compilation succeeds:

```make
./$(COMPILER) --target=xtensa --xtensa-abi=windowed test/test_emit_obj.pas ...o
readelf -h ...o | grep -q 'REL (Relocatable file)'
```
```make
# the windowed ABI picks a7 as the frame pointer, not a15 — it must at least
# lower (no runner: windowed images link through xtensa-esp-elf-gcc)
@./$(COMPILER) ... >/dev/null && echo "xtensa windowed inline asm lowers ok"
```

A compile-only row cannot fail for any reason a *running* program can fail for,
so the entire windowed backend has been gated on "the compiler did not crash".

## The justification in that comment is no longer true

> *no runner: windowed images link through xtensa-esp-elf-gcc*

That was the reason there is no execution row, and it has been overtaken.
**Hosted windowed programs run today under plain `tools/run_target.sh xtensa`** —
that is how the 129-source differential measured windowed at 53 and then 94 of
129 matching the x86-64 oracle. No gcc, no ESP toolchain, the same runner every
Call0 row already uses. Whatever was true when that comment was written, the
runner exists now and nothing was updated to notice.

## What the gap cost, concretely

`bug-a-a-perf-commit-silently-fixed-41-xtensa-windowed-divergences-and-nobody-knows-why`:
41 windowed programs were **SIGBUS**ing on an unaligned data section — not
producing subtly wrong values, dying on signal 7 — and were fixed as an
accidental side effect of a qemu *performance* commit. Nobody noticed the
breakage and nobody noticed the repair. Both are invisible to every gated suite
in this repo, because the only instrument that has ever executed a windowed
program is a scratch harness in one agent's `/tmp`.

That harness dies with the session. **This ticket exists so the finding does
not.**

## Do NOT scope this as "port the 129 rows"

One executed windowed row in a gated suite is worth more than a plan for all of
them, and it is the row that would have caught this. The cheapest useful version
is a single program that reads a multi-word data descriptor — the shape that
faults on a misaligned data section:

```make
./$(COMPILER) --target=xtensa --platform=posix --xtensa-soft-mulhigh \
    --xtensa-abi=windowed test/test_cross_record.pas $(TESTTMP)/xt_win_record
./$(COMPILER) test/test_cross_record.pas $(TESTTMP)/xt_win_record_x64
tools/run_target.sh xtensa $(TESTTMP)/xt_win_record > $(TESTTMP)/xt_win_record.out 2>&1; \
  tools/expect_same.sh xtensa-windowed/test_cross_record-rc "$$?" "0"
tools/expect_same.sh xtensa-windowed/test_cross_record \
  "$$(cat $(TESTTMP)/xt_win_record.out)" "$$($(TESTTMP)/xt_win_record_x64)"
```

**Two rows, not one, and the first draft of this ticket got it wrong.** It wrapped
the runner in `$$(...)`, which keeps stdout and discards the status — and **a
SIGBUS is a status, not a string.** That row would have compared truncated output
and reported a *value mismatch* for a signal death: the right verdict for the
wrong reason, and the wrong diagnosis handed to whoever read it. Corrected by
frank-optimize-b4, which had fixed the same defect in 20 cross-target rows the
same night.

Worth stating plainly because of where it landed: **the row written to catch a
crash was itself written with one outcome slot for a subject that has two.** The
existing `test_xtensa_sigdfl` row two screens up already uses the correct form
(`> /dev/null 2>&1; expect_same "$$?" "143"`) — the pattern was in this same
target and was not copied.

The sharpest instance of the family, also b4's, is worth carrying here for the
next person writing a row: the two `test_asmcore_*` rows ran
`binary | tail -1 | grep -q`, and a pipe eats the status while the success line
is printed *before* the crash — so they were **green through an entire window in
which the binary was segfaulting.** Both slots wrong, in the direction that reads
as healthy.

Measured: that exact row FAILS at `75d2ba662^` (SIGBUS) and PASSES at
`75d2ba662`. It is a real canary, not a hopeful one.

**Named here so it can be folded into the alignment fix in one pass** rather
than sequenced behind it — frank-optimize-b4 is in `elfwriter.inc` now, and this
row is the only pre-merge check that exists for the property its change moves.

## After the one row

Sensible growth, in order, each worth doing only once the one above is green:

1. Three or four more from the aggregate/RTTI family (`test_cross_dynarray`,
   `test_interfaces`, `test_cross_sets`) — the shapes that actually faulted.
2. A windowed section in `test-xtensa` rather than rows scattered among Call0
   ones, so the count is visible and a future reader can see it is 4 and not 107.
3. Only then consider whether the differential belongs in the repo as a tool.

## Why prio 60

Same number as the bug it protects, and for the reason the two are one problem
from opposite ends: a correctness property propped up by a perf constant, and a
correctness property with no gate, are the same exposure. Fixing the alignment
without adding the row leaves the next person exactly where this one started.

## Note on the track letter

Filed A+S rather than T. The gap is in `test-xtensa`, a Makefile target owned by
the lane that owns the backend, not in Track T's `testmgr`/`twatch` tooling. If
it later grows into a differential runner it becomes T's; one Makefile row is
not that.

## RESOLVED 2026-08-30 (frankS) — five executed windowed rows in `test-xtensa`

`test-xtensa` now ends with a windowed section: **107 Call0 rows + 5 windowed**,
the first executed windowed programs in the repo's history.

The five, one per aggregate/RTTI family, each picked because it was **measured
red** rather than because it looked relevant — all five are in the set of 41 that
flipped between `75d2ba662^` and `75d2ba662`:

| source | family |
| --- | --- |
| `test_cross_record` | records — multi-word descriptors |
| `test_cross_dynarray` | dynamic arrays — length/refcount header |
| `test_interfaces` | interfaces — vtable/RTTI through two indirections |
| `test_cross_sets` | sets — multi-word bitmaps |
| `test_cross_variant` | variants — payload word after a byte tag |

Two outcome slots each, per the correction b4 made to this ticket's own draft.

### The rows are proven able to go red — and the failed attempt is the useful half

Against the pre-repair compiler (`41e452a55913` = `75d2ba662^`) all five die on
**signal 7** and **both slots fire**: rc reports exit 135, value reports differing
output. Note which slot carries the diagnosis. Without the rc slot the failure
reads as a value mismatch and the SIGBUS is invisible — which is precisely the
defect b4 caught in the draft.

**What did NOT reproduce it: setting `ELF_DATA_ALIGN = 1` at HEAD leaves all five
GREEN.** I expected a red and got a green, and the green is the finding. `readelf
-lW` on a windowed binary shows the data section in its **own PT_LOAD at offset
`0x30000`** — b4's split (`3b8d1039e`) page-aligns it independently, so
`AlignCodeForData` is currently **redundant on the executable path** and
`CheckDataBaseAligned` cannot fire there.

That is belt-and-braces on a property that cost 41 programs, not a defect. But it
means **these rows are not measuring the explicit invariant today**, and anyone
who later removes the PT_LOAD split must not read their green as evidence the
alignment call still holds the property up. Recorded in the Makefile beside the
rows, where that reader will be standing.

Had I not run the negative experiment I would have written "proven red" on the
strength of the old-compiler run alone, which is true and would have implied
something false.

### A second finding, filed separately

`bug-t-the-esp-bare-suite-is-in-no-tier-so-nothing-ever-runs-it` [T+S p45].

b4 had already added the executed windowed canary — **into `test-esp-bare`**,
which appears in **zero** testmgr tiers and in no script. So the row existed, was
correct, used the right two slots, and still could not fail anything. **The same
defect one level up:** this ticket's complaint was a suite whose pass and whose
skip print the same thing; that is a row whose pass and whose non-execution print
the same thing. Adding a correct row to an unenrolled target moves the
invisibility instead of removing it, and a Makefile target looks gated when you
are reading the Makefile. That is why the five went into `test-xtensa`, which is
enrolled in `full`.

### Scope held

Only the `test-xtensa` target was edited. `test-esp-bare` was left alone —
b4's row there is a harmless duplicate of one of these five and is b4's to keep
or drop. Nothing in `compiler/**` was committed; the `ELF_DATA_ALIGN` change was
a local experiment, reverted, and the tree rebuilt to a clean fixedpoint.

### Items 1-3 of "After the one row"

Item 1 (three or four more from the aggregate/RTTI family) is done — that is what
these five are. Item 2 (a windowed *section* rather than scattered rows, so the
count is visible) is done: the section header states the count and why it is 5
and not 107. Item 3 (whether the differential belongs in the repo as a tool) is
deliberately **not** done and should stay a separate decision.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.

## APPENDIX — the harness's provenance, banked because the harness does not survive

Track S stands down with this ticket, and the 129-source differential lives in a
session scratch directory that dies with it. The five rows above are the part
that survives as *code*; this is the part that would otherwise have to be
re-derived from scratch. Everything here is a measurement, not a recollection.

### The binaries the baselines were taken at

| tag | sha256 (12) | what it is |
| --- | --- | --- |
| `cc-preelfpage` | `41e452a55913` | `75d2ba662^` — before the accidental repair |
| `cc-elfpage` | `a3f0f9e3325f` | `75d2ba662` — the perf commit that masked it |
| `cc-align` | `62cfb924053f` | `df98fea47` — b4's explicit alignment |

Sweeps ran per-ABI with flags
`--target=xtensa --platform=posix --xtensa-soft-mulhigh [--xtensa-abi=windowed]`,
each program's stdout compared against the same source compiled for x86-64 by
**the same binary** (self-oracle, so a compiler-wide regression cannot hide by
moving both sides).

### The partition that matters: 53 -> 94 windowed

| | |
| --- | --- |
| windowed MATCH at `75d2ba662^` | **53** |
| windowed MATCH at `75d2ba662` and at `df98fea47` | **94** |
| flipped red -> green | **41** |
| lost in either direction | **0** |

**The 41 are not "unlucky" programs, and this is the sentence to keep:** the
misalignment was universal and always was — the other 53 were never safe, only
untested. A predicted `code mod 4` split between the two groups was run and
**refuted** (both groups are congruent to 3 mod 4), which is what replaced "41
unlucky programs" with the universal reading and changed what the repair had to
be.

### The 41, by name, so the canary set can be extended without re-deriving it

  - `test_arm32_virtual_wide.pas`
  - `test_array_of_const_types.pas`
  - `test_class_of.pas`
  - `test_collections.pas`
  - `test_const_record_temp_managed.pas`
  - `test_cross_const_alias.pas`
  - `test_cross_dynarray.pas`
  - `test_cross_float_const.pas`
  - `test_cross_record.pas`
  - `test_cross_record_array_store.pas`
  - `test_cross_set_param.pas`
  - `test_cross_setlen_varparam.pas`
  - `test_cross_sets.pas`
  - `test_cross_typed_const.pas`
  - `test_cross_variant.pas`
  - `test_cross_variant_payload_widths.pas`
  - `test_cross_write_pchar.pas`
  - `test_dynarray_copy.pas`
  - `test_dynarray_copy_nested.pas`
  - `test_dynarray_field.pas`
  - `test_dynarray_global_after_method.pas`
  - `test_dynarray_whole_assign.pas`
  - `test_forin_implicit_field.pas`
  - `test_forin_member_access.pas`
  - `test_forin_member_temp_zeroinit.pas`
  - `test_frozen_string_cross_b305.pas`
  - `test_inheritance_dispatch.pas`
  - `test_interface_arc.pas`
  - `test_interfaces.pas`
  - `test_interfaces_as.pas`
  - `test_interfaces_inherit.pas`
  - `test_interfaces_is.pas`
  - `test_interfaces_multi_secondary.pas`
  - `test_interfaces_param.pas`
  - `test_managed_record_temp_init.pas`
  - `test_method_implicit_field.pas`
  - `test_nested_dynarray_setlen.pas`
  - `test_set_runtime.pas`
  - `test_shortstring_trunc.pas`
  - `test_variant_class_cross.pas`
  - `test_variant_self_assign_is_a_no_op.pas`

### Still not matching under windowed at `df98fea47` (35 of 129)

  - `lib_bignum_ops.pas` (CFAIL)
  - `test_arm32_arg_runtime.pas` (DIFF)
  - `test_asm_ifdef_multiarch.pas` (DIFF)
  - `test_asm_rv32.pas` (X64SKIP)
  - `test_asyncecho.pas` (CFAIL)
  - `test_call_result_member.pas` (DIFF)
  - `test_channel.pas` (CFAIL)
  - `test_classref.pas` (DIFF)
  - `test_conformance_2.pas` (CFAIL)
  - `test_cross_exception.pas` (CFAIL)
  - `test_cross_float.pas` (DIFF)
  - `test_cross_managed_aggregate_locals.pas` (DIFF)
  - `test_cross_string.pas` (DIFF)
  - `test_cross_syscall.pas` (DIFF)
  - `test_cross_trunc_round_saturate.pas` (DIFF)
  - `test_ctor_string_literal_arg.pas` (CFAIL)
  - `test_eof_stdin.pas` (DIFF)
  - `test_extern_c.pas` (CFAIL)
  - `test_extern_c_float.pas` (CFAIL)
  - `test_hidden_dynarray_temp_zeroinit.pas` (CFAIL)
  - `test_lfm.pas` (DIFF)
  - `test_overflow_checks_qplus.pas` (CFAIL)
  - `test_overflow_qplus_narrow.pas` (CFAIL)
  - `test_reactor.pas` (CFAIL)
  - `test_rtti.pas` (DIFF)
  - `test_scheduler.pas` (CFAIL)
  - `test_scheduler_exc.pas` (CFAIL)
  - `test_signal_handler_callback_b336.pas` (CFAIL)
  - `test_signal_pc_rewrite.pas` (CFAIL)
  - `test_signal_siginfo.pas` (CFAIL)
  - `test_signal_sp_rewrite.pas` (CFAIL)
  - `test_streaming.pas` (DIFF)
  - `test_streaming_enumset.pas` (DIFF)
  - `test_timer.pas` (CFAIL)
  - `test_variant_comparison_coerces_a_stringy_operand.pas` (CFAIL)

### Call0 and riscv32, for completeness

Call0 **104**/129 and riscv32 **111**/129 at `62cfb924053f`, both unchanged
across the alignment work with `lost=0 gained=0` by set difference. Those two
targets tolerate unaligned word loads, so they could never have gained from the
fix — they were measuring its *cost*, and it is zero.

### How to rebuild the harness if it is ever wanted

It is roughly 60 lines of Python. Take the cross-target Pascal sources listed
above as the corpus; compile each one twice with the same compiler binary (once
with the xtensa flags named above, once bare); run the xtensa image through
`tools/run_target.sh xtensa`; compare stdout; bucket into MATCH / DIFF / CFAIL.
The two traps that cost real time, both worth stealing:

1. **Stamp every result file with target, ABI, and the compiler's sha256.** A
   tag collision silently overwrote an xtensa result with a riscv32 one and
   produced 13 regressions that did not exist.
2. **Compare row SETS, never counts,** and assert
   `matches_before - lost + gained == matches_after`. An equal count hides an
   equal swap, and the windowed row is exactly where that would have mattered.

Whether a differential like this belongs in the repo as a real tool is item 3 of
the growth list above and is deliberately still open.
