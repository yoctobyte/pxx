# Prompt to self — next fresh session (Track C+B+A, master)

You are **Track C+B+A** (C frontend + libraries + compiler) on frankonpiler,
working directly on `master`. Combined-track rule: a change to shared compiler
internals is filed as a Track A ticket but you may self-resolve it. Read
`devdocs/dev/parallel-tracks.md` if unsure.

## Prime directive (user, 2026-07-05)

**Prove Pascal AND C stable before anything new. NO Nil-Python / new frontends
until then.** Real-world C programs are the proven bug-finders — keep grinding
them until the cross targets are solid.

## Where things stand (all pushed, master green)

Variadic C ABI is DONE on all 5 targets; `va_list` is an array typedef
(pass-by-pointer); **C `long` is now native** (8 on LP64, 4 on ILP32) — that was
the keystone that made **arm32 printf incl `%f` byte-identical to x86-64**.
x86-64/aarch64/i386/arm32 printf all byte-identical. Gate held: `make test` +
self-host byte-identical + `test-{i386,arm32,riscv32}` green. Key commits:
`2647f41f` `c5f80ac6` `74d6d4b7` `1b12f4a6`.

Read first: ticket `devdocs/progress/unfinished/feature-c-cross-lua-sqlite.md`
(full bug log, items 1-17), and memory
`project_cross_variadic_arm32_riscv32_v178.md`,
`project_aarch64_signed_subword_load_sqlite_v177.md`,
`project_cross_lua_aarch64_green_v176.md`.

## Open loose ends — hunt these to "stable" (rough priority)

1. **arm32 + i386 lua/sqlite emit GARBAGE output.** They BUILD now (variadic +
   long fixed the ABI) but run wrong — separate 32-bit codegen bugs, unrelated to
   variadic. Highest signal: `make test-lua-cross LUA_CROSS_TARGETS=arm32` /
   i386, then bisect a single script (e.g. `strings.lua`) with `__pxx_write`
   markers in `builtin/*.pas` or the lua .c. Expect a handful of real 32-bit
   codegen bugs (string/number/table/hash paths). This is the big one.
2. **riscv32 printf = softfloat.** `pascal26:...: __pxx_dcmp not found (uses
   softfloat?)` — riscv32 `%f`/double formatting needs the softfloat compare/
   convert kernels wired (see `ir_codegen_riscv32.inc` softfloat helper lookups).
   Blocks riscv32 printf/lua/sqlite entirely.
3. **typedef-array-param → pointer decay (cfront correctness, ticket item 17).**
   `va_list ap` param types as by-value `tyRecord` instead of decaying to a
   pointer (cfront drops the array dim of an array-typedef param). No longer on
   printf's critical path (long=native keeps va_list in regs) but still wrong for
   >4-word va_list args. Fix: (a) `ParseCTypedef` record the `[N]` of
   `typedef T Y[N]`, (b) param loop `cparser.inc ~4777-4806` apply the pointer
   decay when the resolved param type is an array typedef. Minimal repro:
   `inner(int,int,int,int, Box b)` with `typedef struct{int a;} Box[1]` SIGSEGVs
   on arm32; plain-pointer 5th arg works.
4. **Wire green cross runs into make targets** — `test-lua-cross` exists
   (aarch64), extend to arm32/i386 once green; add `test-sqlite-cross`. NOT in
   `make test` (3rd-party + qemu).
5. **Fresh real-world C target** once cross is greener — see
   `backlog/idea-c-realworld-test-targets.md` (busybox `cat` = top pick, then
   tcc). North star: compile gcc.

## Gates (every compiler change)

`make test` + self-host byte-identical (`make all`) on x86-64 host; keep
`test-{i386,arm32,riscv32}` green; aarch64 lua stays 6/6
(`make test-lua-cross`); x86-64 sqlite/lua unchanged. Commit small, push when
your lane is green. LANDMINE: compiler self-host has no IntToStr — never use it
in `Error()` strings.

## Debug tactics that worked this arc (reuse)

- x86-64 native is fastest to debug (no qemu) — favor generalizations validated
  on x64 first.
- qemu + gdb-multiarch: `set sysroot ~/.cache/pxx-cross/<arch>`; frame-walk by
  fp when symbols absent; addr2line filename/line is unreliable (cfront skips
  `#if 0`).
- Instrument 3rd-party C with file-scope `extern long __pxx_write(int,const
  void*,unsigned long);` + block decls before statements (cfront rejects
  mid-block extern). Exit codes are 8-bit — probe one small value per run.
- A/B a suspected regression against the pre-change compiler via `git stash`.
- pxx struct layout == gcc for plain structs — a standalone offsetof-probe TU
  gives field names; BFS an object graph for ASCII strings to ID a struct.
