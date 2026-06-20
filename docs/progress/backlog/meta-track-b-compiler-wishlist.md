# Track-B wishlist — compiler features most wanted to unblock libraries + demos

- **Type:** meta (priority index)
- **Status:** backlog
- **Owner:** — (track B requests; track A implements)
- **Opened:** 2026-06-19
- **Relation:** the single place track A can pull from to maximize track-B
  throughput. Each item links its own detail ticket; ranked by how many
  library/demo deliverables it unblocks. Companion to
  feature-rtl-conversion-and-bitset-library and the demo/library tickets.

## How to read this

Ranked by **unblock-leverage** (deliverables freed ÷ effort), highest first.
"Unblocks" lists the concrete `feature-*-library` / `feature-demo-*` work that
is waiting on it. Track B has interim workarounds where possible; these remove
them.

## Ranked wishlist

### 1. 64-bit operators + literals  →  `bug-64bit-shift-xor-literal-gaps`
The single biggest unlock. Three defects in one:
- `xor` operator unrecognized
- `shl`/`shr` by >= ~31 return 0 (64-bit shift is effectively 32-bit)
- 64-bit hex literals truncate to 32 bits (+ `UInt64(...)` cast unrecognized)
**Unblocks:** `feature-hashing-library` (SHA/CRC/MD5 need xor + 64-bit rotates),
the real `feature-random-library` (xoshiro256**/splitmix64), 64-bit limbs in
`feature-bignum-library`. **Interim:** 32-bit LCG RNG shipped; bignum uses
base-1e9 Int64-decimal limbs.

### 2. Case-insensitive builtins  →  `bug-builtin-write-case-sensitive`
`WriteLn`/`Write`/`ReadLn` mixed case unresolved (user idents already are
case-insensitive). Cheap fix, broad reach.
**Unblocks:** `examples/adventure` and any FPC-cased demo (lisp/calc/solitaire
will all use mixed case). No clean interim (can't lowercase idiomatic source).

### 3. Loadable `sysutils` unit  →  `bug-sysutils-unit-hard-skipped`
`uses sysutils` is hard-skipped, so a real `lib/rtl/sysutils` can't load.
**Unblocks:** the canonical RTL home for IntToStr/Val/StrToInt/Copy/Trim (the
`feature-rtl-conversion-and-bitset-library` surface). **Interim:** helpers live
in `lib/rtl/strutils`.

### 4. Generic `Copy` intrinsic (+ siblings)  →  `feature-copy-intrinsic`
Dynarray sub-array (generic over T), 2-arg `Copy(s,i)`, string-family overloads,
by-type resolution. Same wall for `Delete`/`Insert`/`Concat`.
**Unblocks:** `feature-json-library` and string-heavy code broadly. **Interim:**
`strutils.Copy(AnsiString)` only.

### 5. Sets from runtime values  →  `feature-language-gaps-from-demos` (Gap 1)
`[v]` with variable v errors; `Include`/`Exclude` unimplemented.
**Unblocks:** `feature-sat-solver-library`, `feature-demo-maze` set-lane, the
sudoku set-lane. **Interim:** bitmask / boolean-grid stand-ins.

### 6. Record-returning fn codegen crash  →  `bug-record-fn-codegen-crash`
Context-sensitive runtime crash in a record-returning fn with nested loops over
dynarray fields (the fused `BigMul`; possibly the maze segfault).
**Unblocks:** general numeric kernels in `feature-bignum-library` and beyond.
**Interim:** BigMul rebuilt on simpler primitives.

### 7. Temporary as const record arg  →  `bug-const-byref-record-param-temp`
`f(g(x))` illegal when the param is a `const` record (forces named locals).
**Unblocks:** ergonomic value-style APIs everywhere (bignum, JSON nodes,
vectors). **Interim:** intermediate variables.

### 8. Generator record-yield + nested-yield  →  `feature-language-gaps-from-demos` (Gaps 2-3)
`yield` from a nested routine; `generator of <record>` consumed by `for-in`.
**Unblocks:** `feature-demo-chess` movegen, generator-based demos. Unverified
(needs a build to confirm).

## Also needed (RTL, not pure compiler — noted for sequencing)

- **Text file I/O** (`Assign`/`Reset`/`Rewrite`/`ReadLn(f,...)`/`Eof`/`Close`,
  `{$I-}`/`IOResult`) — blocks `examples/adventure` save/load. Track-B RTL work
  over the kernel-ABI file syscalls, but may need a builtin hook; see the
  adventure `EXPECTED-FAILURES.md` F1/F2.

## Already landed (track A)

- const-expr `shl`/`shr`/`mod` folding (`632f1c8`) — done.
- **Item 1 — 64-bit ops (`7d4ea89`) — DONE.** xor + UInt64 alias + aarch64 udiv.
  splitmix64 byte-identical on all 4 targets. Frees hashing / real RNG / 64-bit
  bignum.
- **Item 2 — case-insensitive Write/WriteLn/Read/ReadLn (`3de5d05`) — DONE.**
  Frees the FPC-idiomatic / mixed-case demos (adventure, lisp, calc...).
- **Item 3 — loadable `sysutils` (`66a3dec`) — DONE.** `uses sysutils` loads
  lib/rtl/sysutils.pas if present (graceful no-op otherwise); compiler's own
  uses is {$ifdef FPC}-guarded so it can't pull a user RTL unit. **Track B: the
  canonical RTL home is open — migrate the conversion helpers into
  lib/rtl/sysutils.pas.**

**Stable v10 pinned (`93ad58a`)** — items 1-3 + COM/ARC interfaces are in track
B's pinned binary (binary+builtin coherent; v9->v10).

### Recommended next-pull order (track A)

0. **Re-verify the codegen crashes on v10 first** (cheap, high-info). The
   bignum/maze segfaults were last seen against pinned v9 mid-WIP; v10 is freshly
   stabilized + builtin-coherent. Reconstruct the crashing shape from
   `bug-record-fn-codegen-crash` and run it. Either it is GONE (close that ticket
   + the maze segfault, drop B's `BigMulSmall` workaround) or it is REAL (now
   bisectable on a clean compiler). `bug-const-byref-record-param-temp` (item 7)
   can be spot-checked in the same pass.
1. **Item 5 — sets from runtime values** (`feature-language-gaps-from-demos`
   Gap 1): `[v]` with a variable + `Include`/`Exclude`. Self-contained codegen;
   unblocks THREE demos at once (SAT solver, maze set-lane, sudoku set-lane), all
   on bitmask/boolean-grid stand-ins today. Highest demos-per-hour.
2. **Item 4 — generic `Copy`** (+ `Delete`/`Insert`/`Concat`): unblocks the JSON
   library + string-heavy code. Bigger (needs by-type overload/generic
   resolution), so third not second.

## Log
- 2026-06-19 — opened by track B as the prioritized pull-list. Top unlock is
  item 1 (64-bit ops): it frees hashing, real RNG, and 64-bit bignum at once.
  Items 2-3 are cheap and free the FPC-idiomatic demo + the canonical RTL home.
- 2026-06-19 — **items 1-3 all landed by track A** (commits above). Items 4-8
  remain.
- 2026-06-19 — **stable v10 pinned** (1-3 + interfaces handed to B). Next-pull
  order set: re-verify crashes on v10, then item 5 (sets) for max demo unlock,
  then item 4 (Copy) for JSON.
- 2026-06-19 — **stable v11 pinned (`90f706a`)**: items 4, 5, 6, 7 all landed.
  Item 6 (`bug-record-fn-codegen-crash`) was GONE on v10 (v9 mid-WIP artifact),
  closed. Item 7 (const-record-temp) fixed. Item 5 (runtime sets +
  Include/Exclude) done. Item 4 — **dynarray `Copy` done**; string-family
  overloads + `Delete`/`Insert`/`Concat` siblings still open under
  `feature-copy-intrinsic`. **Items 1-7 now all in B's pinned binary.**
  Remaining wishlist: **item 8** (generator record-yield + nested-yield, Gaps 2-3,
  UNVERIFIED — needs a build) and the Copy siblings. Two pre-existing cross bugs
  surfaced + filed (`bug-const-managed-record-param-byref-crash`,
  `bug-dynarray-whole-var-assign-cross`; both i386+aarch64, x86-64 fine).
  Suggested next: **item 8** (verify/enable generator record + nested yield →
  unblocks chess movegen) or the `Copy` siblings (`Delete`/`Insert`/`Concat`) for
  JSON breadth.
- 2026-06-20 — **track B library upgrades using landed wishlist items:**
  - `random.pas` upgraded from interim 32-bit LCG to xoshiro256** + SplitMix64
    (enabled by item 1 — 64-bit ops). LCG retained for constrained targets.
    Slices 1–2 of feature-random-library done.
  - `bignum.pas` gained `BigMul` (schoolbook) and `BigSub` (enabled by item 6 —
    record-fn codegen crash fixed). `BigMulSmall` kept as fast path.
  - `sysutils.pas` gained `FloatToStr`, `FloatToStrF`, `StrToFloatDef`,
    `StrToFloat`, `Pos`, `PadLeft`, `PadRight`. Discovered that the `Str` builtin
    breaks when sysutils's `Copy` is in scope — filed as a compiler gap.
