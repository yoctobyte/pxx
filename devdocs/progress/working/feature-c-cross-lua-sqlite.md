# Cross-target lua 5.4 + sqlite3 — build & run on all backends

- **Type:** feature (test coverage / cross-codegen hardening) — Track C+B+A
  (C frontend + crtl headers + shared codegen). crtl headers = B (file-owned);
  cross C→IR / backend bugs found = A (file A ticket, self-resolve under the
  combined-track rule).
- **Status:** working — Phase 1 (crtl headers) DONE. Phase 2 **aarch64 lua 5.4
  GREEN** (`make test-lua-cross`, 6/6). Phase 3 **aarch64 sqlite3 GREEN** —
  `csqlite_extended_test.c` runs under qemu-aarch64 with **byte-identical output
  to x86-64** (CRUD, transactions, COUNT/SUM/AVG, floats 2000.75/35.00). 14 cross
  bugs fixed total. Remaining: variadic ABI for arm32/i386/riscv32 (their
  lua/sqlite build-fail at the "not yet" gate), then their runs; wire a
  `test-sqlite-cross` make target.
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

8. **Unsigned integer compares on aarch64** used signed condition codes
   (`EmitSetccA64` always lt/le/gt/ge) — this was the `limit=-1` wall.
   `luaM_limitN`'s guard `cast_sizet(MAX_INT) <= MAX_SIZET/sizeof(ls_byte)` (=
   `<= 0xFFFF…F`) went FALSE because 0xFFFF…F read as -1, so the else branch
   returned `cast_uint(0xFFFF…F) = -1` as the opcode-array limit → "too many
   opcodes (limit is -1)". The 4-byte Instruction case had slipped through only
   because `MAX_SIZET/4 = 0x3FFF…F` reads positive-as-signed. Added
   `EmitSetccA64Ex(op,isUnsigned)` → lo/ls/hi/hs; the compare site passes
   unsigned when either operand is an unsigned ordinal.
9. (bonus, same root family) the two-step diagnosis above also depended on the
   #6 unsigned-div and #7 `~`-type fixes to get `MAX_SIZET/N` right first.

**Phase 4 (partial):** `make test-lua-cross` added (LUA_CROSS_TARGETS, default
`aarch64`); mirrors test-lua's skip guard, runs each script under qemu vs the
same .expected. Green for aarch64. NOT wired into `make test`.

**Phase 3 — aarch64 sqlite3 (commit de9741a0):** compiles + links (6.3MB, 3861
procs) and `sqlite3_open(":memory:")` works. Bugs fixed to get there:
10. crtl VFS headers (B): fcntl.h, inttypes.h, sys/{stat,time,ioctl,mman}.h +
    time.h timespec/nanosleep/clock_gettime + utimes. Declarations only (the
    :memory: DB never calls the file VFS; they just must compile/link).
11. **fn-ptr param with a `(void)` signature dropped from ParamCount** — parsing
    `void (*x)(void)` leaked global CTypeIsVoid so the outer param list skipped
    the whole fn-ptr param. GENERAL bug (x86-64 silently miscompiled, pushing a
    garbage extra arg; aarch64's strict arg-count check caught it). Fix in
    cparser: clear CTypeIsVoid once the declarator is a pointer.
12. **@extern** (address of an external routine) for aarch64 + arm32 (was
    x86-64-only) — reuse the GOT-slot machinery with a load instead of a call
    (sqlite aSyscall[] pointer table). symtab.inc EmitExternalProcAddr.
13. aarch64 external variadic calls guarded (fcntl/open `int f(int,int,...)`).

**14. sqlite CREATE TABLE segfault (aarch64) — FIXED (bug-aarch64-signed-subword-load-32bit-extend).**
Root cause: **narrow signed loads (`ldrsb`/`ldrsh`) sign-extended to only 32 bits,
not 64.** `ir_codegen_aarch64.inc` emitted the 32-bit-Wt variant (opc=11,
`$39C0…`/`$79C0…`) for signed byte/half loads. Since aarch64 W-register writes
zero the top 32 bits, a stored `i8 = -1` (0xFF) loaded via `ldrsb w0` became
`x0 = 0x0000_0000_FFFF_FFFF` — then used in a **64-bit** compare it reads as a
large POSITIVE number. sqlite's `BtCursor.iPage` (i8, init `-1`) thus tested
`iPage >= 0` TRUE, so `moveToRoot` took the "page already loaded" branch with
`pCur->pPage == NULL` → NULL deref in `getAndInitPage`/`sqlite3PagerPageRefcount(
pPage->pDbPage)`. Fix: emit the 64-bit-Xt sign-extending variant (opc=10,
`$3980…`/`$7980…`) at all 8 signed sub-word load sites (IR_LOAD_MEM deref +
EmitLoadVar global/ref-param/local; `sz=4` already used `ldrsw`=64-bit, correct;
unsigned `ldrb`/`ldrh` zero-extend to 64 via top-zeroing, correct). Matches
x86-64's `movsbq`/`movswq`. GENERAL bug — any negative i8/i16 compared/used as
64-bit on aarch64 was wrong; only surfaced here because the value flowed into a
signed `>= 0` guard. DEBUG PATH: 18-deep qemu stack → walked frame chain by x29
→ identified crashing struct via BFS of its object graph for ASCII strings
(":memory:", "sqlite_master", column names) → `BtCursor` (iPage@84 i8, pPage@136)
→ pxx struct layout == gcc (verified via a standalone offsetof-probe TU), so gcc
`ptype /o` gave field names. Marker recipe (decl-style, cfront-safe): `long
__pxm = __pxx_write(2,"[tag]\n",N);` among the function's leading decls.

**PRIOR WALL (now cleared) — sqlite CREATE TABLE segfault (aarch64):** minimal repro = the
extended-test head (SQLITE_THREADSAFE 0 + amalgam includes) with body
`sqlite3_exec(db,"CREATE TABLE t(x INTEGER)",0,0,&e)`. x86-64 rc=0; aarch64
SIGSEGV after "DB opened". Fault at a tiny accessor `f(arg){ …arg->[0x70]… }`
with arg=NULL; its caller passed `P->[0x88]` which is NULL on aarch64 but set on
x86-64. So a struct pointer field at offset 0x88 is unpopulated. NARROWED via
`__pxx_write` markers: the initial CREATE codegen runs fine; `sqlite3EndTable` is
entered TWICE (codegen with init.busy=0, then during the **schema reparse** with
init.busy=1 = the in-memory-representation insert). The crash is in that
**schema-load path** (VDBE `OP_ParseSchema` re-running the CREATE to build the
in-memory Table), AFTER EndTable's `sqlite3HashInsert` — not the first codegen.
So the NULL field is on a Table/Schema struct built during schema load. Bitfield
struct layout was verified identical aarch64-vs-x86-64, so suspect a larger/
nested struct offset, an aggregate initializer, or a field written on one path
and read on another with a mismatched offset. Debug: gdb-multiarch via
`qemu-aarch64 -g`; instrument the schema-load callbacks (sqlite3InitCallback /
the OP_ParseSchema VDBE handler) and trace who writes struct+0x88. Marker recipe:
file-scope `extern long __pxx_write(int,const void*,unsigned long);`, block decls
before statements (cfront rejects mid-block `extern`). The sqlite tree is
gitignored scratch — debug edits there are untracked and were reverted.

**Then (future session):**
- **arm32/i386/riscv32 variadic ABI** — the callee register-save prologue is
  aarch64-only (`cparser.inc` EmitCSetjmpStubs' sibling: the vaSave block raises
  "variadic C functions … not yet supported on this cross target"). They need a
  4-byte-slot save area + a `__pxx_va_arg_cross32` helper (arm32: r0-r3 then
  stack; i386: pure cdecl stack; riscv32: a0-a7). Until then their lua/sqlite
  build-fails at the first variadic fn (printf).
- Then each target's lua run (same unsigned-div/compare fixes likely already
  cover arm32/riscv32, which branch on signedness; i386/x86-64 were fine).
- Then **Phase 3 sqlite** cross (csqlite_extended_test.c per target).
- Debug tip: instrumenting 3rd-party lua .c with `__pxx_write(2,…)` markers is
  the fast cross probe — but the C frontend rejects a mid-block `extern`; put
  the extern at file scope and all block decls before statements.

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
