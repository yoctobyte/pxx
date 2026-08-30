---
track: A+S
type: feature
prio: 50
status: working
found: 2026-08-30
found-by: frankS
owner: frankS
---

# Xtensa implements 31 IR ops; riscv32 implements 45 and aarch64 53

Every source `test-riscv32` uses, compiled for hosted xtensa: **66 of 142 do not
compile**, and `IREmitNodeXtensa` raises
`target xtensa: unsupported node in IR codegen: <op>` for most of them. This
ticket is the scoping pass that the oracle ticket deferred, and the list below
is its own acceptance criterion — the gap is countable and has a known end.

## The 14 ops both riscv32 AND aarch64 have and xtensa does not

```
IR_CLASSREF        IR_READ_DISCARD    IR_SET_CMP
IR_COPY_REC_MANAGED IR_READ_VAR       IR_SET_COPY
IR_DYNUNIQUE       IR_SETLEN_DYN      IR_SET_LIT
IR_FRAME           IR_SET_BINOP       IR_SET_SIGNAL
IR_READLINE        IR_STORE_DYN
```

There is no op xtensa has that riscv32 lacks, and none that riscv32 has and
aarch64 lacks — so riscv32's arm is a complete superset to port from, and it is
the closest ABI (32-bit, same helper set, same 4-byte slot model). **Port, do
not re-derive.** Four missing-row bugs were fixed on xtensa on 2026-08-30 by
porting verbatim, and a re-derivation is a second implementation
([[devdocs/dev/normalise-dont-special-case]]).

## What the 66 actually are — measured, one compile each

| cause | count | owner |
| --- | --- | --- |
| **missing IR op** (`setlen_dyn` 8, `rtti_reg` 6, `copy_rec_managed` 4, `dynunique` 2, `set_lit` 2, `set_copy` 1, `readline` 1) | **24** | **this ticket**, `ir_codegen_xtensa.inc` |
| no xtensa row in the POSIX syscall table (`SYS_openat`, `SYS_gettid`) | 15 | `lib/rtl/platform/posix/platform_backend.pas` — Track B; separate ticket |
| needs `--threadsafe` | 8 | **not an xtensa gap** — the test's own invocation |
| `builtin calls not supported in bare-metal stage N` | 6 | separate; may be profile selection, not a gap |
| signal `SA_SIGINFO` | 4 | [[feature-signal-siginfo-ucontext]] |
| dynamic symbols (`dlopen`, `atoi`, `atof`) | 3 | **by design** — this backend emits no dynamic segment |
| inline asm for another arch (`test_asm_arm32`, `test_asm_rv32`) | 2 | **by design** |
| `SetLength` on a var-array parameter | 2 | this ticket (adjacent to `IR_SETLEN_DYN`) |
| aggregate result via a virtual call | 1 | [[feature-cross-virtual-indirect-hidden-dest]] |
| non-scalar function result | 1 | this ticket |
| **total** | **66** | |

So **this ticket unblocks about 28 of the 66**, not all of them, and five of the
remaining categories are somebody else's or are correct behaviour. Recorded that
way deliberately: a ticket that claims the whole 66 would be closed while
two-thirds of the list was still red.

`rtti_reg` appears in the failures but not in the 14-op list above, because it is
handled outside the node dispatch on the other backends — it is in scope here
anyway; the six `class of` / RTTI programs need it.

## Ordering

By programs unblocked: `IR_SETLEN_DYN` + `IR_STORE_DYN` + `IR_DYNUNIQUE` (the
dynamic-array family, ~10), then `rtti_reg` (6), then `IR_COPY_REC_MANAGED` (4 —
and it is also one of the seven rows missing from xtensa's scope-exit release,
[[bug-a-xtensa-scope-exit-releases-one-of-seven-managed-kinds]], so the two want
doing together), then the set family (`SET_LIT`/`SET_COPY`/`SET_BINOP`/`SET_CMP`,
3+), then the read family.

## Gate

Per op: `make compiler/pascal26` (the self-host fixedpoint) plus the newly
compiling programs run and match the x86-64 oracle. At the end: the 142-source
differential with no regression, and `test-xtensa` regenerated from the measured
list. Call0 and windowed both, since several of these ops involve calls and the
two ABIs marshal differently — that asymmetry is what caused
[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]].

## Bound

Object-level, hosted xtensa profile, Call0, `--xtensa-soft-mulhigh`, at
`37171a6b1`. Op counts obtained by parsing the three backends' case labels, not
by reading them; the 66 categories by compiling each source once and taking its
first error. Not checked under the windowed ABI, and not on real or emulated ESP
silicon.

## PROGRESS — the dyn-array + managed-record family landed, 2026-08-30

`IR_SETLEN_DYN`, `IR_DYNUNIQUE`, `IR_STORE_DYN`, `IR_COPY_REC_MANAGED` ported
from riscv32. Measured against a **clean** baseline — the first attempt was
confounded by a rebase that pulled in Track A's pointer-aligned array frame slot
(`599000083`), which alone moves five float/aggregate programs, so the
pre-change compiler was rebuilt at HEAD and swept again. Both compilers are
self-host fixedpoints of the same tree:

| | HEAD `3b567373c1ef` | +this `fbfb0b6e991b` |
| --- | --- | --- |
| MATCH | 69 | **84** |
| CFAIL | 52 | **38** |
| DIFF | 7 | **6** |
| regressions | — | **NONE** |

Windowed measured separately: 45 matching before and after, no regression. The
13 newly-compiling programs all DIFF under windowed, and that is
[[bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength]]
— plain `SetLength(a, 8)` on a local, code predating this work entirely, already
SIGBUSes under windowed at HEAD. Verified, not assumed.

### Two bugs the ops UNCOVERED, both now fixed

**A missing op hides every bug in the programs it stops from compiling.** This is
the general form of the ticket and it paid out twice in one commit:

1. `test_dynarray_whole_assign` did not compile, so nothing had ever run what it
   asserts — and the whole-array store arm it exists to check (`b := a`,
   `IR_STORE_SYM`) was **also** missing on xtensa, the last backend without it.
   Adding the ops made the program compile and SEGFAULT. Confirmed pre-existing
   by rebuilding the HEAD compiler and reproducing, not by assuming.
2. `Halt(n)` exited **zero** — filed and fixed as
   [[bug-a-halt-n-exits-zero-on-hosted-xtensa]]. Its invisibility is a *third*
   mechanism: the test ran, was green, and asserted stdout instead of the exit
   code.

With both stores now retaining, the seventh managed kind of the scope-exit
release (local dynamic array) became safe and is enabled;
`test_managed_local_release_reuse` is 5/5.

### Corrected denominator

The sweep list is the **129-source** union of `test-riscv32` and `test-xtensa`,
reconstructed from the current Makefile. The earlier `142` in this ticket and in
the `test-xtensa` header **cannot be reproduced** from the Makefile at any
target combination (`test-riscv32` alone is 127, `+test-arm32` is 141). Treat
the partition as N/matching, not as a fixed denominator; the 66/24 category
table above was measured against the old list and its *categories* stand while
its totals do not.

### Remaining on this ticket

`rtti_reg` (6 programs), the set family (`SET_LIT` / `SET_COPY` / `SET_BINOP` /
`SET_CMP`), the read family (`READLINE` / `READ_VAR` / `READ_DISCARD`),
`IR_CLASSREF`, `IR_FRAME`, `IR_SET_SIGNAL`, plus `SetLength` on a var-array
param and the non-scalar function result. 38 sources still do not compile.
