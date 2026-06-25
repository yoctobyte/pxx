# Plan — C frontend test ladder (sha256 → sqlite → lua)

Status: roadmap / strategy note (2026-06-25). Not a ticket; the work lives in
`feature-c-source-frontend` (frontend), `feature-c-runtime-library` /
`lib/crtl` (the libc slice), and the per-target ABI tickets. This doc records
*which* real C programs to compile, in *what order*, and *why* — so the C track
is bug-discovery against real code, with a free oracle at every rung.

## Premise

C is (roughly) a subset of the Pascal AST the compiler already lowers: no managed
types (no AnsiString, no dynamic arrays), no RAII. So the C frontend is mostly
"parse C, map to the existing IR." The interesting work is at the edges — the
libc slice C code calls (`lib/crtl`) and two ABI features (varargs, setjmp).

The strategy is **real apps as probes**, not synthetic corner-poking: a large,
clean, portable C program exercises a huge swath of the frontend + backend in one
shot, and the good ones **ship their own test suites** — instant correctness
oracle, no hand-written expectations.

## Why sqlite is the flagship

- Deliberately portable ANSI C, no GNU extensions, amalgamated to one
  `sqlite3.c`. The friendliest 250k-line monster available.
- External surface is tiny: basically **file I/O** (through a pluggable VFS you
  can shim onto the PAL — in-memory or single-thread file VFS), optional
  threading (compile single-threaded), and its **own internal `printf`** (the one
  hard dependency: varargs).
- **Ships millions of test cases.** Compile sqlite, run sqlite's own harness, and
  it tells you if your codegen is correct. One app, enormous coverage, free
  oracle. One sqlite > 100 toy demos.
- Avoids `setjmp`/`longjmp` — which is exactly why it comes before lua.

**Done-signal for the whole C track:** *our-compiled sqlite passes sqlite's own
test suite.* That single milestone means "the C frontend is real."

## The ladder — each rung adds exactly one hard feature

Sequenced so that when a rung breaks, the cause is the one new thing it
introduced (the "limit the landscape" rule — small blast radius per step).

| Rung | Program(s) | New capability exercised | Oracle |
| --- | --- | --- | --- |
| 0 | sha256 / md5 / blake2; TweetNaCl | pure int math, rotations, fixed arrays. No malloc, no I/O, no varargs, no setjmp | official test vectors; A/B vs `lib/rtl/hashing` |
| 1 | cJSON; miniz | heap (malloc/free), structs, pointers | own tests; A/B vs Pascal `json` / `zlib` |
| 2 | **sqlite** | varargs (internal printf), file VFS | sqlite's own harness |
| 3 | lua | setjmp/longjmp, GC, heavy varargs | lua's own test suite |

Rung 0 is the first C program to compile: if a hash matches its published vector,
the integer codegen is sound. Everything else builds on that.

Avoid early: `stb_image` (uses setjmp), `dtoa`/`ryu` (float→string corner-hell —
great bug-finder, punishing first), `tcc` (inline asm + GNU-isms).

## crtl — the libc slice (and the musl 2-for-1)

sqlite/lua don't need much libc: `malloc`/`free`, `memcpy`/`memmove`/`memset`,
`qsort`, `string.h` family, a little `math.h`, `strtod`, and `vsnprintf`. That is
`lib/crtl` (`feature-c-runtime-library`, currently blocked on the frontend).

Two ways to build crtl:

1. **Hand-write the minimal slice in Pascal** to bootstrap sqlite. Fastest path
   to a running sqlite.
2. **Compile musl's clean C implementations with our own frontend.** musl is the
   most readable libc; its `string`/`stdlib`/`stdio` pieces *are* the crtl we
   need, and compiling them is itself a frontend test — crtl built in the language
   it serves. Chicken-and-egg (needs the frontend first), so this is the *second*
   move: hand-write minimal crtl → stand up the frontend on sqlite → optionally
   re-host crtl from musl C.

musl also gives the cleanest reference for the two ABI gates below (its
`setjmp.S` / `va_*` are ~20 lines per arch).

## Gate 1 — varargs (`va_list` / `va_arg`)

C has no managed types, so **no varrec machinery is needed** — the Pascal
`array of const` lowering is irrelevant here. But the vararg type set is not just
int/pointer:

- **Default argument promotions:** `float` → `double`, `char`/`short` → `int`.
  So `printf("%f", x)` reads a `double`. The set is {int, int64, pointer,
  **double**}.
- Structs-by-value through `...` are legal C but rare; `printf`-family never do
  it, and sqlite/lua don't. Out of scope until something needs it.

The real work is the **per-target ABI**, not the types:

- **x86-64 SysV / aarch64:** a variadic callee must spill its incoming argument
  registers (GP + SSE/FP) into a **register-save-area** in its frame; `va_arg`
  then walks gp_offset/fp_offset and the overflow (stack) area. This is the hard
  part — variadic function prologues differ from normal ones.
- **i386 / arm32:** trivial — all varargs land on the stack, so `va_list` is just
  a moving stack pointer.

sqlite forces this (its internal `printf`), so it is on the critical path
regardless. Implement and verify on x86-64 first (host baseline), then aarch64.

## Gate 2 — setjmp / longjmp (non-local jump)

What it is: C's non-local goto / poor-man's exceptions.

- `setjmp(env)` saves the current execution context — the callee-saved registers,
  the stack pointer, and the return PC — into `env` (a `jmp_buf`). On the direct
  call it returns `0`.
- `longjmp(env, val)` restores that saved context: execution jumps back to the
  `setjmp` call site, which "returns" a *second* time, now with value `val`
  (nonzero). It unwinds the stack frames between the two without running anything
  (C has no destructors). Used for error propagation: lua `longjmp`s to a
  protected-call boundary; `stb_image` longjmps out of a decode on error.

Why it sounds scarier than it is **for this backend**:

- `setjmp`/`longjmp` are inherently arch asm primitives — musl writes them in asm,
  not C. So implement them as **per-arch asm stubs in `crtl`**, ~20 lines each:
  `setjmp` stores callee-saved regs + SP + return address into the buffer and
  returns 0; `longjmp` loads them back, sets the return register to `val`, and
  jumps to the saved PC (restoring SP = the unwind). The C *frontend* never
  compiles these from C.
- `jmp_buf` is just a fixed-size byte buffer sized per arch (enough for the
  callee-saved set + SP + PC).
- The one compiler obligation is the **"returns twice" hazard**: a local that is
  live across a `setjmp` and modified before the `longjmp` must not be kept only
  in a register, or its post-longjmp value is indeterminate (the C standard
  requires `volatile` for the strict case). **Our unoptimized, stack-spilling
  codegen sidesteps this for free** — if locals live on the stack across calls,
  the second (longjmp) return observes correct values. So a naive codegen is
  accidentally correct here; the asm stub does the rest.

Net: setjmp/longjmp = a small per-target asm stub + a `jmp_buf` size constant, and
our spill-happy codegen avoids the classic optimizer trap. It is a nameable
milestone, not a research project — which is why lua (needs it) sits one rung
above sqlite (doesn't).

## Sequencing summary

```
hand-write minimal lib/crtl
        │
sha256 / TweetNaCl   (rung 0: int codegen + vectors)
        │
cJSON / miniz        (rung 1: heap + structs; A/B vs Pascal libs)
        │
sqlite               (rung 2: varargs + file VFS; sqlite's own harness)  ← flagship
        │
lua                  (rung 3: setjmp + GC)
        │
optionally: re-host crtl from musl C (frontend self-test)
```

Each rung: clean landscape, one new gate, a free oracle. See
`feature-c-source-frontend`, `feature-c-runtime-library`,
`docs/developer/c-interop.md`, and `docs/developer/frontends-and-targets-strategy.md`.
