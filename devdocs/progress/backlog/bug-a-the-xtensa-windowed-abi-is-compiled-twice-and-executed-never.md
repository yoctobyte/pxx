---
slug: bug-a-the-xtensa-windowed-abi-is-compiled-twice-and-executed-never
track: A+S
prio: 60
type: bug
blocked-by: []
status: backlog
found: 2026-08-30
found-by: frankS
owner: unassigned
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
