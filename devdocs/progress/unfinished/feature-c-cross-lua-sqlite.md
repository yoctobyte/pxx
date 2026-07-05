# Cross-target lua 5.4 + sqlite3 — build & run on all backends

- **Type:** feature (test coverage / cross-codegen hardening) — Track C+B+A
  (C frontend + crtl headers + shared codegen). crtl headers = B (file-owned);
  cross C→IR / backend bugs found = A (file A ticket, self-resolve under the
  combined-track rule).
- **Status:** working — Phase 1 (crtl headers) DONE. Phase 2 **aarch64 lua 5.4
  GREEN** (`make test-lua-cross`, 6/6). Phase 3 **aarch64 sqlite3 GREEN** —
  `csqlite_extended_test.c` runs under qemu-aarch64 with **byte-identical output
  to x86-64** (CRUD, transactions, COUNT/SUM/AVG, floats 2000.75/35.00). 14 cross
  bugs fixed total. **Variadic C ABI now on all 5 targets.** i386 (commit
  c5f80ac6) printf incl %f is byte-identical to x86-64 — i386's all-stack cdecl
  passes the 24-byte va_list by value naturally, so printf→__crtl_vformat works.
  arm32 + riscv32 direct va_arg works (2647f41f) but printf/lua/sqlite there are
  blocked on va_list-passed-by-value (needs array-typed va_list or 32-bit
  struct-by-value >8B). i386 lua/sqlite get far but hit separate i386 gaps
  (external-call arg-count mismatch, a lua segfault). Then wire test-*-cross.
  **UPDATE (session #2, commits `eb972e79` heap + `8b94020b` arm32 variadic
  straddle):** the "arm32/i386 lua garbage" was a single shared 32-bit
  heap-corruption bug (PXXAlloc/Realloc stepped 8 while PWord writes 4 on ILP32) —
  FIXED; then arm32 numeric.lua's doubles fixed via the variadic 8-byte-straddle
  read fix. **arm32 cross lua now 6/6 (wired into `make test-lua-cross`, default
  `aarch64 arm32`); aarch64 6/6; i386 5/6** (only coroutines.lua left). Remaining:
  i386 coroutines.lua (coroutine stack); riscv32 softfloat. See progress log item 18.
- **Owner:** Track C+B+A (combined)
- **Opened:** 2026-07-05

## Progress log (session 2026-07-05 #3, riscv32 hosted C brought up to near-lua)

**19. riscv32 hosted C lua — from "won't link" to "runs all init + scalars, one
remaining table-rehash corruption."** Chain of fixes (all committed, test-riscv32
green, self-host byte-identical, x86-64 lua 6/6 + cross 18/18 unaffected):
- **`fix(cfront)`: pull pxxcio+softfloat for hosted riscv32 C** (ParseCProgram
  skipped ALL riscv32; Pascal path only skips ESP-bare). Hosted riscv32 C had no
  runtime bridge — `__pxx_write`/malloc unresolvable, every double failed
  "__pxx_dmul not found". Now float C runs (verified dmul/malloc/write).
- **`fix(crtl)`: libc-free ungetc/system + auto-pull for sscanf helpers.**
  stdio.c used bare `extern strtol/strtod/isspace` instead of #include, so the
  crtl auto-pull never linked their bodies → unresolved externals on the static
  riscv32 image. Added `#include`s; added a one-char pushback slot to FILE for
  ungetc (honored by fgetc AND fread — lua's loader peeks a '#!'/BOM then
  bulk-reads); added a `system()` stub. riscv32 printf now byte-identical to x64.
- **`feat(riscv32)`: C callee reads >8-word params from the stack** (mirror the
  Pascal riscv32 spill: word k>=8 at [s0+16+(pnWords-1-k)*4]). The IR_CALL site
  already pushed them; only the C prologue errored.
- **`fix(riscv32)`: long-range calls via auipc+jalr not JAL (+/-1MB).** THE big
  one — cross lua is 1.75MB, so main and most callees sit past JAL's reach; the
  truncated offset jumped to garbage and segfaulted before any output. auipc+jalr
  (RISCVPcrelSplit) gives full 32-bit range; patched EmitCallProc (symtab.inc),
  ApplyCallFixups (both words), and the ParseCProgram entry stub.
- **Result:** riscv32 lua now LINKS and RUNS — through ALL library init and these
  work: `print(42)`, `print(3.14)`, `print("hi")`, `print(1+2)`, recursion
  `f(5)`, table LITERALS `{1,2,3}` + reads `t[2]`.

**RESOLVED (session #3b→c): riscv32 lua now 6/6 — ALL FOUR cross targets pass
lua 6/6 (24/24), riscv32 wired into `make test-lua-cross` default.** Two fixes:
- **`fix(riscv32)` large stack frames (>2047B) truncated the prologue addi** (THE
  table-corruption bug). The prologue reserved the frame with one
  `addi sp,sp,-frame`, but addi's imm is 12-bit signed (±2048). luaV_execute's
  3312B frame → `-3312` truncated to +784 → prologue moved sp UP, leaving locals
  below sp where callees overwrote them (the "wild store of 16" = the corrupted
  pointer). Fix: reserve 3 prologue words, patch `addi+2nop` (small) or
  `lui t0,hi; addi t0,t0,lo; sub sp,sp,t0` (large). GENERAL riscv32 bug — fixed
  latent breakage in ANY large-frame riscv32 function, not just lua.
- **`fix(riscv32)` file seek**: rv32 syscall 62 is `_llseek` (5-arg, result
  pointer), not plain lseek → PalBackendSeek passed NULL → EFAULT; plus the
  `__pxx_seek` extern was native-`long` vs Pascal `Int64`. Fixed the _llseek shape
  + widened the extern to `long long`. Unblocked files.lua.

LESSON: the "heisenbug + wild store of a small constant" signature = a stack-frame
sizing/overflow bug; check the PROLOGUE frame reservation against the target's
immediate range FIRST (each backend's PatchProcPrologue has its own limit).

--- historical (the hunt that led here) ---
**REMAINING riscv32 lua bug (razor-sharp repro): storing a NEW key that triggers
rehash crashes.** `local t={} t[1]=5` (or `t.x=9`) SIGSEGVs; `local t={1,2,3}` +
`t[2]` read is fine (array preallocated, no rehash). Localized via `__pxx_write`
markers in ltable.c: the crash is in the `luaH_newkey`→`rehash`→`luaH_resize`
path. It is a HEISENBUG — adding markers moves the crash point downstream, the classic
MEMORY-CORRUPTION signature. arm32/i386 pass this, so it is riscv32-specific.

**Deep localization (session #3b, gdb on the clean binary — addresses stable, no
ASLR under qemu-user):**
- Trigger is table GROWTH specifically: `t[1]=5`/`t.x=9`/`t={5,6,7};t[4]=8` all
  crash (any rehash/resize); `t={0};t[1]=9` (existing slot), all GETS, and
  `{1,2,3}` literals are FINE. So the bug is on the SET-that-grows path only.
- The crash instruction is in `luaV_execute` (`lw a0,0(a0)` deref of a corrupt
  pointer). The corrupt value is **`0x10` = 16 = `nsize` = `newasize*sizeof(TValue)`
  = 1*16**, i.e. an allocation BYTE SIZE landed in a pointer slot.
- Ruled OUT with minimal repros: the crtl heap/realloc (malloc torture bad=0 on
  riscv32), indirect-call-returning-pointer (works), `luaM_realloc_` itself
  (returns a valid pointer, `nb=` dumped fine), Node/Table/TValue sizeof (24/32/16,
  IDENTICAL to arm32 — layout is consistent), and the rehash SIZE computation
  (na=1 nh=0, identical to arm32).
- WILD STORE confirmed via gdb: in `luaV_execute` the local `[s0-8]` (fixed stack
  addr, e.g. 0x2b2aaaf8) = a valid pointer (0x81fe8e0) BEFORE the `luaV_finishset`
  call and = 0x10 AFTER it returns. Breaking at `luaH_resize` entry+exit and
  `luaH_newkey` entry+exit shows the slot INTACT there — so the wild store is in
  `luaV_finishset`'s value-insertion, NOT in resize/newkey. Something writes 16 to
  a stack address ABOVE the callee frames (a positive-offset / out-of-bounds store
  relative to a callee's s0).
- **NEXT (needs better tooling — qemu-riscv32 has NO hardware-watchpoint support,
  and the victim stack slot is reused across frames so single-address gdb tracking
  is ambiguous):** either (a) disassemble `luaV_finishset` + `luaH_set` +
  `reinsert`/`luaH_newkey` looking for a STORE with a POSITIVE offset off s0/sp (a
  local-address miscomputed as +N instead of -N, or a `TValue aux`/`k`
  16-byte-write overflowing its slot upward), or (b) run under a riscv32
  record/replay or valgrind-equivalent. The value being exactly 16 = one
  `sizeof(TValue)` strongly implicates the array-grow store sequence
  (`t->array = newarray; setempty(&t->array[0])`) or the `luaH_set` that re-inserts
  the value after rehash. Break addrs (this binary): luaH_resize 0x81333a4,
  luaH_newkey 0x8134d94, rehash 0x8134138, setnodevector 0x8132248, reinsert
  0x8132dbc, luaV_finishset 0x8149b74. crtl instrumentation in
  library_candidates/lua is gitignored scratch — reverted clean.

## Progress log (session 2026-07-05 #2, 32-bit heap corruption ROOT-CAUSED + FIXED)

**18. THE "arm32/i386 lua/sqlite emit garbage" BUG — FIXED (commit `eb972e79`).**
It was NOT garbage output or per-backend codegen — it was **one shared 32-bit
heap-corruption bug**. `builtinheap.pas` PXXAlloc (zero-on-reuse) and PXXRealloc
(grow-copy) loops walk with `PWord` (= `^NativeInt`, machine-word: **8 bytes on
64-bit, 4 on 32-bit**) but advanced the index by a **hardcoded 8**. On ILP32 each
PWord write moves 4 bytes while the loop steps 8, so bytes [0-3],[8-11],… are
written and **[4-7],[12-15],… are skipped**: every `realloc` silently dropped
half the payload, reused blocks were half-uninitialised. Any 32-bit program doing
real realloc corrupted — lua/sqlite hammer realloc, so BOTH i386 and arm32 broke;
x86-64 was fine only because there NativeInt=8=step. Fix: step by
`SizeOf(NativeInt)` in both loops. Also retyped the crtl↔RTL bridge
`__pxx_malloc/__pxx_realloc` params `Int64`→`NativeInt` (latent width mismatch vs
their C `long` externs after long=native; byte-identical on x86-64).
- **Diagnosis path that worked** (record for reuse): the symptom (lua reserved
  words lexed as NAMEs → `'end' expected near 'end'`, and layout-sensitive
  heisenbug segfaults — reached LOAD-ERR under gdb, segfaulted standalone) pointed
  at interned-string-table corruption. Ruled out narrow-load (item-14 family) and
  luaS_hash with tiny standalone C repros (both byte-identical across targets).
  Then a **malloc/realloc torture repro** (alloc→memset(i)→realloc→verify first
  bytes) gave `bad=47` on arm32/i386 vs `bad=0` on x86-64 — isolated it to the
  allocator in ~15 lines, no qemu-gdb spelunking needed. LESSON: when a heavy real
  program corrupts on 32-bit only, torture the allocator FIRST.
- **Result:** cross lua **5/6 on arm32, 5/6 on i386** (was total corruption).
  Remaining fails are separate narrower bugs, NOT this one:
  - **arm32 numeric.lua — FIXED (commit `8b94020b`), arm32 cross lua now 6/6.**
    Root cause: arm32 variadic 8-byte args STRADDLE the r0-r3/stack boundary
    (pxx packs 64-bit variadic args as two unaligned words, so one spans the
    reg/stack boundary — low word in r3, high on the stack). `__pxx_va_arg_cross32`
    skipped the leftover reg word and read the whole 8 bytes from overflow →
    dropped the low half + over-advanced, shifting every later arg. Fix (read side
    only, NO call-site change → no mixed/integer regression): assemble the straddler
    from its two halves into the 176-byte __va_save slack (arm32 uses 16 of 176).
    First tried a call-site pad word instead — it fixed pure doubles but REGRESSED
    lua's mixed integer varargs (desync with the tail-reversal); reverted. The
    read-side assemble in stdarg.h is the correct, regression-free fix. i386 lua
    unchanged (all-stack cdecl never straddles). Reduced to pure C:
    `printf("%g %g %g",1.0,2.0,4.0)` gave 1st right / rest garbage before the fix.
    - **Minor cfront finding (separate, not blocking):** a SMALL `long long`
      literal like `100LL` is typed `tyInteger` (fits in int), so as a variadic
      arg it is pushed as ONE word and `va_arg(long long)` misreads it. Large
      int64 literals (>2^32) and int64 *variables* pass correctly. C conformance:
      the `LL` suffix should force `long long` regardless of value. Low priority.
    Minimal repro & traces:
    - pxx passes each variadic 8-byte arg (double / int64) as TWO packed words,
      NO 8-byte alignment (ir_codegen_arm32.inc variadic-tail push ~2071-2089;
      stdarg.h cross32 comment "packed (no 8-byte alignment)"). The first 4 arg
      words load into r0-r3, the rest go to the stack.
    - So after e.g. one named int word (`cnt` in r0) + one double (r1:r2), the
      NEXT double's low word lands in **r3** and its high word on the **stack** —
      it straddles the register/stack boundary.
    - `__pxx_va_arg_cross32` (lib/crtl/include/stdarg.h) can't read a straddling
      arg: when `gp_offset+8 > regsize` it *consumes the leftover reg word* (skips
      r3) and reads the whole 8 bytes from overflow(stack) → gets [hi-of-arg,
      lo-of-next] = garbage. Confirmed by C repros (`/tmp/va*.c`):
      `fd(3,1.0,2.0,4.0)` → `xY yN zN`; single double/int64 (j≤4) work
      (`iY dY`); but ANY multi-8-byte-arg variadic call fails, even for args that
      sit fully in registers (`j5`: 1 named + two int64, 1st int64 in r1:r2 still
      reads N once a straddling 2nd arg follows) — so there is ALSO a
      frame/reg-save interaction beyond the pure straddle, needs gdb on __va_save.
    - **i386 numeric.lua PASSES** — i386's all-stack cdecl has no reg/stack
      boundary, so it never straddles. This is why the bug is arm32-only.
    - **FIX DIRECTION:** make 8-byte variadic args 8-byte-aligned so they never
      straddle — i.e. at the call site insert a padding word when an 8-byte arg
      would start at word index 3 (the only straddle position for a 4-word reg
      area), AND seed `regsize`/`gpbytes` + reg-save consistently so
      `__pxx_va_arg_cross32`'s existing "skip leftover reg word, read from
      overflow" path lines up with the padded layout. Must also re-check the
      variadic-tail reversal (~2157) and the multi-arg in-register failure. Keep
      the aarch64/i386/riscv32 paths and the non-variadic Int64 ABI unchanged;
      gate on the existing va_arg exit-code tests + test-lua-cross arm32.
  - **i386 coroutines.lua — FIXED (commit `49b7cbd6`), i386 cross lua now 6/6.**
    Root cause: the hand-written i386 `__pxx_longjmp` stub read env/val from
    standard-cdecl slots ([esp+4]=env, [esp+8]=val), but pxx's i386 ABI pushes
    args leftmost-deepest (arg0 at the HIGHER offset) — so env(arg0) is at [esp+8],
    val(arg1) at [esp+4]. longjmp dereferenced the small int val as a jmp_buf →
    segfault. setjmp (1 arg) was fine ([esp+4] either way). Lua coroutines ride
    setjmp/longjmp (yield longjmps to resume). Fixed by swapping the two loads.
    Pure-C repro: nested setjmp/longjmp (x86-64/arm32 pass args in registers, were
    fine). **All three cross targets aarch64+arm32+i386 now 6/6 (18/18), wired
    into `make test-lua-cross` default.**

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

**15. arm32 + riscv32 variadic C ABI — DONE (direct va_arg), commit `2647f41f`.**
The va_arg machinery (was x86-64 + aarch64 only) now covers the 32-bit cross
targets. Verified end-to-end via exit codes under qemu (int / int64 / pointer
sequences, in loops, order-sensitive across the reg/stack boundary):
- Frontend: `__builtin_va_arg` → size-driven `__pxx_va_arg_cross32(ap,size)`
  (4-byte word slots, 64-bit steps two); `__builtin_va_start` →
  `__pxx_va_start_impl32(ap,save,gpbytes,overflow,regsize)`. Reg-save prologue:
  riscv32 saves a0..a7, arm32 saves r0..r3 into `__va_save`.
- Call site: variadic-tail 64-bit args now pushed as 2 words (the ParamCount
  gate skipped them, dropping the high word); arm32 reverses its variadic stack
  tail so the callee's forward va_arg walk reads args in order.
- LANDMINE (fixed): arm32 must use r12 scratch (not an arg reg) to compute the
  overflow anchor `fp+8` — clobbering r0 corrupted the first named param before
  the param-copy read it (surfaced only when the callee re-read a named param,
  e.g. a loop bound `i<n`).

**16. i386 variadic C ABI — DONE (commit c5f80ac6), printf incl %f byte-identical
to x86-64.** i386 has no arg registers (all-stack cdecl) and normally pushes
leftmost-deepest (reversed) to match the callee's reversed spill — undecodable
for a variadic callee. Fix, variadic-call-only: call site pushes ALL args in
reverse index order → FORWARD layout (arg0 at [ebp+8]) via an order array (reuses
the per-type push logic; 64-bit tail arg = two dwords); callee named-spill uses
the forward disp (params to the LEFT) for variadic fns; prologue reg-area size 0,
overflow = [ebp+8+namedBytes]. i386's all-stack ABI passes the 24-byte va_list by
value naturally, so printf→__crtl_vformat "just works" (unlike arm32/riscv32).
LANDMINE self-caught: the float branch's arg-advance wasn't converted to the
order array → a double param not-last reprocessed the next arg under the wrong
index (non-variadic regression); all advance sites now go through the order
array. i386 lua/sqlite get much further but hit SEPARATE i386 gaps: sqlite = a
non-variadic "external call argument count mismatch" (ir_codegen386 external
path's strict nArgs=ParamCount check); lua = a SIGSEGV (unrelated i386 codegen).

**17. va_list → array type (commit 74d6d4b7), the by-value blocker below is
CLEARED for the simple case.** `typedef struct __pxx_va_elem va_list[1]` — a local
`va_list` is still 24 bytes on the stack (no alloc) but the bare name decays to a
pointer, so `printf → __crtl_vformat(va_list)` passes a pointer, not a 24-byte
copy. ONE-line change: cfront already handles the array typedef, `CVaListAddr`'s
`&ap` is right for both local (→&ap[0]) and a param (already a decayed pointer) —
compiler binary byte-identical. Verified: x86-64/aarch64/i386 printf incl %f
byte-identical (no regression); direct va_arg on all 5 targets unchanged; simple
`printf→helper` va_list-passing now works on arm32/riscv32.

**REMAINING arm32/riscv32 printf blocker — ROOT-CAUSED: cfront drops the array
dimension when an array-TYPEDEF is used as a PARAMETER.** `va_list ap` (with
`typedef struct __pxx_va_elem va_list[1]`) should decay the param to a pointer
(C: array params → pointers). Instead cfront types it as a BY-VALUE `tyRecord`
(the struct) — confirmed via a DBGPUSH writeln in the arm32 call loop:
`inner`'s `ap` param = `tk=5 (tyRecord) isarr=0`. The explicit-bracket decay at
`cparser.inc:4780` only fires on a literal `T name[...]`, never for a
typedef-array param. Consequence on arm32: the by-value-record push (the
`RecSize<=8` branch, ir_codegen_arm32.inc ~2090) pushes the arg as TWO words
(`&ap` + garbage r1) instead of one pointer word, shifting every following arg
so the callee reads `ap` from the wrong stack slot → helper gets ap=NULL →
SIGSEGV. x86-64/aarch64 tolerate it (real struct-by-value + `&ap` still lands on
the copy); i386 tolerates it (all-stack). It only surfaces once crtl's `size_t`
(=`unsigned long`=8 on arm32, see below) pushes the va_list arg past r3 onto the
stack. Minimal repro (no va_list): `inner(int,int,int,int, Box b)` with
`typedef struct{int a;} Box[1]` SIGSEGVs; a plain-pointer 5th arg works.

**FIX (well-scoped cfront work, the real "A"):** make a typedef-array PARAMETER
decay to a pointer, the same as `T name[...]`. Needs (1) `ParseCTypedef` to
record the array dimension of `typedef T Y[N]`, and (2) the param loop
(`cparser.inc` ~4777-4806) to apply the pointer decay when the resolved param
type is an array typedef. Then `va_list` params are 1-word pointers on every
target and printf works uniformly. (Verified the array typedef itself is fine
for LOCALS + direct va_arg on all 5 targets; only the PARAM decay is missing.)

**RESOLVED (commit 1b12f4a6): `long` is now native (machine-word-sized).**
`long`/`size_t`=8 on LP64 (x86-64/aarch64, unchanged/byte-identical), 4 on ILP32
(i386/arm32/riscv32); `long long` always 64-bit. 3-line ParseCDeclType change,
crtl typedefs follow automatically. **arm32 printf incl %f now byte-identical to
x86-64** — size_t=4 keeps crtl snprintf's va_list arg in a register, dodging the
typedef-array-param stack bug (which still exists for the >4-word case but is no
longer hit by common printf). make test + self-host + test-{i386,arm32,riscv32}
green (fixed one test that hardcoded long=64). STILL OPEN: riscv32 printf =
softfloat (__pxx_dcmp, %f); arm32/i386 lua/sqlite build but emit garbage / hit
separate 32-bit codegen bugs; the typedef-array-param decay (item 17) is still
worth doing for correctness (>4-word va_list args). The remaining consideration
below is now historical/optional.

**Historical DESIGN NOTE (was future work, now done above): `long` sizing.** pxx made
`long`/`size_t` 64-bit on every target (`sizeof(long)`=8 even on arm32/i386) —
consistent but C-divergent (real ILP32 `long`=4). This is what pushes crtl's
`va_list` arg onto the stack in the first place. Purists / memory-tight targets
(riscv on ESP) may want native `long`. Option **B** — make `long`/`size_t` 32-bit
on 32-bit targets — would ALSO unblock printf (keeps the va_list in registers)
and is more C-correct, but reverses the consistent-64-bit model. Deferred; do the
cfront typedef-array-param decay (A) instead, which is orthogonal and correct
regardless of the `long` choice.

**PRIOR BLOCKER (now cleared for simple case) — va_list passed BY VALUE.** crtl's
`printf` (and sqlite's/lua's own printf) do `va_start(ap,fmt)` then hand the
whole `va_list` (24-byte struct) to a formatter (`__crtl_vformat`, sqlite
`sqlite3VXPrintf`) by value. arm32/riscv32 have no struct-by-value >8 bytes ABI,
so `ap`'s `reg_save_area` pointer arrives garbage → SIGSEGV. Direct va_arg works;
only the pass-va_list-to-a-helper pattern breaks. FIX OPTIONS (next session):
(a) array-typed `va_list` (`typedef struct __pxx_va_elem va_list[1]`) so it
decays to a pointer on any call — but `CVaListAddr` unconditionally emits `&ap`,
which is wrong for an array-decayed *pointer parameter* (double indirection);
needs `__builtin_va_arg`/`va_start` to detect ap-is-already-a-pointer.
(b) 32-bit struct-by-value >8 bytes (or by-hidden-ref) in the arm32/riscv32
backends. Also: riscv32 printf independently needs softfloat (`__pxx_dcmp` …);
riscv32 has a separate int64-local + int-local-both-used codegen bug (an int64
va_arg result added to an int va_arg result dropped the int — `(int)a+b`
returned `a` only; non-variadic pointer-deref equivalent works, so it is a
riscv32 int64-local interaction, not the variadic ABI). i386 variadic still
gated off (reversed cdecl arg order needs a forward-order call-site pass).

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
