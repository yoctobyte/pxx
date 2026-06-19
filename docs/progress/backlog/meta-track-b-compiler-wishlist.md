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

Next pull candidates: item 4 (generic Copy), item 5 (sets from runtime values).

## Log
- 2026-06-19 — opened by track B as the prioritized pull-list. Top unlock is
  item 1 (64-bit ops): it frees hashing, real RNG, and 64-bit bignum at once.
  Items 2-3 are cheap and free the FPC-idiomatic demo + the canonical RTL home.
- 2026-06-19 — **items 1-3 all landed by track A** (commits above). Items 4-8
  remain.
