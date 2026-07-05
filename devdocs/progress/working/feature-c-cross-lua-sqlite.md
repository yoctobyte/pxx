# Cross-target lua 5.4 + sqlite3 — build & run on all backends

- **Type:** feature (test coverage / cross-codegen hardening) — Track C+B+A
  (C frontend + crtl headers + shared codegen). crtl headers = B (file-owned);
  cross C→IR / backend bugs found = A (file A ticket, self-resolve under the
  combined-track rule).
- **Status:** working — Phase 1 (crtl headers) DONE; Phase 2 (cross lua) in
  progress on aarch64: 8 cross bugs fixed, lua now builds + inits + loads all
  libraries; walled at a `limit=-1` opcode-growth miscompile in lcode.c.
- **Owner:** Track C+B+A (combined)
- **Opened:** 2026-07-05

## Progress log (session 2026-07-05, aarch64 first)

Commits: `3f0954bf` (headers + setjmp + variadic + deref), `d3672df7`
(unsigned div), `851ff448` (unary `~` type). All keep x86-64 self-host
byte-identical + `make test` green.

**Fixed (all verified with minimal C repros):**
1. **crtl headers (Phase 1, B):** `float.h`, `time.h`+`time.c`; `__pxx_time`/
   `__pxx_clock` bridges in `pxxcio.pas` (per-arch clock_gettime). Cleared the
   float.h→time.h preprocessor walls.
2. **setjmp/longjmp cross stubs** (`cparser.inc` EmitCSetjmpStubs) — was
   x86-64-only; per-ABI save/restore for i386/aarch64/arm32/riscv32.
3. **Variadic C call site** (aarch64/arm32/i386): strict `nArgs=ParamCount`
   check now bypassed for `ProcVariadic`.
4. **Variadic callee prologue**: SysV register-save was emitted UNCONDITIONALLY
   (x86-64 bytes → SIGILL when a variadic fn was called on cross). Now per-target;
   aarch64 GP-only save area + `__pxx_va_arg_cross`. **arm32/i386/riscv32 raise a
   clear "not yet" error** — their 4-byte-slot variadic model is still TODO.
5. **Deref-of-call double-eval** (all 4 cross backends): statement driver's
   `else` catch-all emitted `IR_LOAD_MEM` standalone, re-running its address
   operand — `*f()` called f twice, corrupting va_arg. Added `IR_LOAD_MEM` to
   each no-op list.
6. **Unsigned 64-bit div/mod on aarch64** used SDIV not UDIV → `MAX_SIZET/N`=0
   → lua bogus "table overflow"; also broke `%lu` of large values. Now keys off
   `TypeDivideUnsigned(IRTk[left])` like arm32/riscv32.
7. **Unary `~` result type** hardcoded tyInteger → `(~(size_t)0)/N` divided
   signed. Now preserves the promoted operand type.

**NEXT WALL (unresolved) — `limit=-1` opcode growth:** aarch64 lua loads all
libs (F:open-done, every `req:` module OK) then fails compiling the test script
bytecode: `LOAD-ERR too many opcodes (limit is -1)`. Traced to
`luaM_growaux_` (lmem.c) receiving `limit=-1` for `what="opcodes"`. The limit is
`luaM_limitN(MAX_INT, Instruction)` = `(cast_sizet(MAX_INT) <= MAX_SIZET/sizeof
(Instruction)) ? MAX_INT : cast_uint(MAX_SIZET/sizeof(Instruction))`. When the
guard comparison is (wrongly) false, the else branch yields `cast_uint(0x3FFF…)
= 0xFFFFFFFF = -1`. **Reproduced in isolation: NONE of the pieces fail** —
`MAX_SIZET/sizeof(Instruction)`, the `<=`, the full macro all return the right
answer standalone. So the miscompile is **context-specific** (large lcode.c
function; suspect register pressure / spill corrupting the div or compare
operands, or a lost unsigned type on the div's left operand in that context).
Debug path: instrument the real `luaM_limitN` at lcode.c:385, then rr/gdb the
aarch64 division+compare in `luaK_code`. Debug markers used this session live in
lstate.c/lmem.c/ltable.c (all reverted; the lua tree is gitignored scratch).

**After that:** finish arm32/i386/riscv32 variadic (4-byte-slot model), then
the remaining lua walls, then Phase 3 sqlite, Phase 4 make targets.

## Goal

Make the real C programs **lua 5.4** and **sqlite3** compile+run on the CROSS
targets (i386, aarch64, arm32, riscv32), not only AMD64. Long stretch of
Pascal-focused compiler work may have left cross C→IR / backend regressions;
these two large real programs are the coverage. External libs — keep OUT of
`make test`; green cross runs go behind their own targets.

## Phase 0 — AMD64 baseline (DONE 2026-07-05, no regression)

- `make test-lua` = **6/6 PASS** (closures, coroutines, files, numeric/floats,
  oop, strings). Lua floats work → the `unfinished/feature-c-desktop-lua-sqlite-
  path` "only float broken" claim is **stale** (update it).
- sqlite extended test passes fully — CRUD, transactions, COUNT/SUM/AVG, floats
  (2000.75, avg 35.00), NULL:
  ```
  ./compiler/pascal26 -g -Ilib/crtl/include -Ilib/crtl/src \
    -Ilibrary_candidates/sqlite test/csqlite_extended_test.c /tmp/x && /tmp/x
  ```
- `make test` + all four `make test-{i386,aarch64,arm32,riscv32}` green (Pascal +
  small C). qemu-i386/aarch64/arm/riscv32 all installed.

## Root cause of the cross gap (diagnosed)

Cross build of lua stops at `#include <float.h>`. `cpreproc.inc:1503` gates the
`/usr/include` host-header fallback on `TargetArch = TARGET_X86_64` — deliberate
and correct (host headers = wrong ABI for a cross target). So cross builds must
resolve every system header from pxx-owned crtl headers (`lib/crtl/include`).

crtl **missing** (present: assert/ctype/errno/limits/locale/math/setjmp/signal/
stdarg/stdbool/stddef/stdint/stdio/stdlib/string/unistd/wchar/wctype + sys,arpa,
netinet dirs):
- lua needs: `float.h`, `time.h`
- sqlite needs: `float.h`, `time.h`, `fcntl.h`, `sys/stat.h`, `inttypes.h`,
  `sys/time.h`

Platform-guarded headers (windows/readline/unicode/malloc/process) are not
reached on a Linux build — ignore them (AMD64 built fine without them).

## Plan (land only green, one phase at a time)

- **Phase 1 (Track B — `lib/crtl/include/**`):** add the missing ABI-neutral
  headers. Start with `float.h` (pure `FLT_`/`DBL_` limit macros — identical
  across all four IEEE-754 targets, zero ABI risk), then `time.h`, then the
  sqlite set. Model on existing crtl headers; keep minimal (only symbols lua/
  sqlite actually reference).
- **Phase 2 (Track A/C — the payoff): cross lua.**
  ```
  ./compiler/pascal26 --target=<T> -Ilib/crtl/include -Ilib/crtl/src \
    -Ilibrary_candidates/lua/src test/lua/runner.c /tmp/lua_<T>
  cp test/lua/<name>.lua /tmp/pxx_lua_input.lua
  tools/run_target.sh <T> /tmp/lua_<T>   # diff vs test/lua/<name>.expected
  ```
  i386 + aarch64 first (fast), then arm32, then riscv32 (slow). Any mismatch/
  crash = shared C→IR / backend cross bug → file a Track A ticket with a minimal
  C repro, then self-resolve. Instrument `builtin/*.pas` / `lib/crtl/src/*.c`
  with writeln for fast cross-debug (no rebuild needed).
- **Phase 3 (Track A/C): cross sqlite** — build+run `csqlite_extended_test.c`
  under qemu per target, same bug-hunt loop.
- **Phase 4:** wire green cross runs into new make targets (`test-lua-cross`,
  `test-sqlite-cross`) — **NOT** into `make test`. Skip gracefully when the lua/
  sqlite trees or qemu are absent (mirror the existing `test-lua` skip guard).

## Gates

Each green cross combo runs correct output under qemu; any compiler change keeps
self-host byte-identical (`make all`) + `make test`. Commit small; push when the
lane's gate is green.

## Landmines

- riscv32/xtensa slow under qemu; **xtensa deprioritized — skip it**.
- New IR op = 3 hookups; a new AST node number can collide across frontends —
  the reason shared-internal changes get an A ticket.
- Clear stale `/tmp/*.ppu` before any "works without flag X" claim.
- Session 2026-07-05 committed `8851f8ae` (impl-side `static;`/`reintroduce;` +
  `PChar(expr)[i]`) on master HEAD; pin still v175 — fine, cross C work uses the
  freshly built `./compiler/pascal26`, not the pinned binary.

## First step

Add `lib/crtl/include/float.h`, then immediately probe the aarch64 lua build to
confirm it unblocks (or surfaces the next wall).

## Related

- [[feature-c-cross-target-feature-coverage]] (entry-stub / small-C cross layer)
- [[feature-c-desktop-lua-sqlite-path]] (AMD64 lua/sqlite milestone — mark float done)
- [[feature-c-runtime-library]] (crtl layer)
