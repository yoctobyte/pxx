---
summary: "Four gcc_diff_probe cases are still tagged `known` but no longer diverge — the compiler bug behind them is fixed, so the tag now hides future regressions in str-chr-nul / str-str-empty / mem-chr-miss"
type: task
track: T
prio: 50
---

# Drop the stale `known` tags on the string.h and _Bool probes

- **Type:** task — Track T (test tooling: `tools/gcc_diff_probe.sh`)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Filed by:** Track A, on closing
  `bug-a-pointer-difference-as-vararg-pushes-8-bytes-on-32bit`.

## What

These three probes are declared `probe <name> known`:

    tools/gcc_diff_probe.sh:173   probe str-chr-nul   known
    tools/gcc_diff_probe.sh:184   probe str-str-empty known
    tools/gcc_diff_probe.sh:247   probe mem-chr-miss  known

They were tagged because they diverged on i386/arm32. **They no longer do.**
The divergence was never in `strchr`/`strstr`/`memchr` — it was the pointer
difference in the probes' own `printf` call being pushed at 8 bytes on ILP32,
which displaced every later argument. That is fixed.

Measured before and after the fix, same tree otherwise:

| target | before | after |
| --- | --- | --- |
| i386 | 0 new, **3 known** | 0 new, **0 known** |
| arm32 | 0 new, **3 known** | 0 new, **0 known** |

## Why it matters now

`known` means "diverges, and we have decided not to be surprised". While the
tag stands, these three can regress back to diverging and the probe will report
`0 NEW divergences` and exit clean. The tag has flipped from suppressing a real
known issue to suppressing a real regression — which is the failure mode a
differential oracle exists to prevent.

## Do

Drop the `known` tag from all three so they are judged normally. Confirm with
`tools/gcc_diff_probe.sh --target i386` and `--target arm32` — both should stay
at 0 new / 0 known.

**`bool-and-negative-zero-int` is stale too — confirmed since filing.**
`bug-a-bool-conversion-does-not-normalise-to-0-or-1` landed and that probe now
passes natively (x86-64 went `1 new, 1 known` -> `1 new, 0 known`). Drop its tag
as well; it is declared at `tools/gcc_diff_probe.sh:1348`.

That leaves `int64-to-double` as the only `known` tag still worth checking — it
has its own ticket (`bug-c-int64-to-double-cast-truncates-on-32bit`) and did NOT
diverge on i386 in these runs, so it may be stale too.

## Note on the pin

The measurements above are against `compiler/pascal26` at HEAD, not `pinned`.
`gcc_diff_probe.sh` defaults to `PXX_STABLE`, i.e. `pinned`, which does not yet
carry the fix — so re-running with the default will still show 3 known until
Track A runs `make pin`. Verify with
`PXX_STABLE=./compiler/pascal26 tools/gcc_diff_probe.sh --target i386`, or wait
for the pin.
