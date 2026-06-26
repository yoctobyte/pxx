# C varargs (va_list / va_start / va_arg) — implementation design

- **Type:** feature (the SOLE remaining lua-core parse gate) — Track C frontend +
  Track A backend codegen
- **Opened:** 2026-06-26
- **Blocks:** lapi, lauxlib, ldebug, lobject (`va_arg(argp, type)` in
  luaL_error / lua_pushvfstring). With this, lua core goes 29/34 -> 33/34.

## Current state (investigated 2026-06-26)
- A variadic prototype `f(int n, ...)` already PARSES (the `...` is skipped) and a
  body that declares `va_list ap` but never uses it compiles. So variadic decl +
  `va_list` (degrades to opaque) already work.
- The gap is the operations: `va_start` expands to `__builtin_va_start` ->
  "call to undeclared function: __builtin_va_start"; same for `__builtin_va_arg`
  / `__builtin_va_end`. And there is no register-save prologue, so even if parsed,
  the variadic args can't be read.

## Chosen approach — System V save-area, fully contained
Gate EVERYTHING to variadic C functions so the Pascal self-host stays
byte-identical (Pascal never emits C variadic functions; non-variadic prologues
are untouched). NO change to the call site is needed.

### 1. va_list type (Track C)
Make `va_list` a real 24-byte struct (System V):
`struct { unsigned gp_offset, fp_offset; void *overflow_arg_area, *reg_save_area; }`
Pass it BY VALUE between functions — it carries `reg_save_area` (a pointer into the
ORIGINATING function's frame, which is alive for the duration of the call), so a
callee (lua_pushvfstring) can `va_arg` on its copy and read the originating
function's saved registers. This matches lua's usage (luaL_error builds argp,
hands it to lua_pushvfstring, never re-reads it).

### 2. Frontend parse (Track C)
- Mark the proc variadic (a `ProcVariadic[]` flag, set in ParseCSubroutine when a
  trailing `...` param is seen).
- Parse `__builtin_va_start(ap, last)` -> AN node; `__builtin_va_arg(ap, type)`
  -> AN node carrying the target type (special-parse the type arg, like sizeof);
  `__builtin_va_end(ap)` -> no-op. Provide lib/crtl/include/stdarg.h defining the
  va_* macros over these builtins + the struct typedef.

### 3. Variadic prologue (Track A backend, ADDITIVE, x86-64)
Only when ProcVariadic: reserve a 176-byte save area on the frame and, at the top
of the prologue, store the 6 GP arg regs (rdi,rsi,rdx,rcx,r8,r9 -> +0..+40) and,
UNCONDITIONALLY, the 8 XMM regs (xmm0..7 -> +48..+168). Saving XMM unconditionally
means the `al` register (vector-arg count) is irrelevant, so NO call-site change /
no al-setup is needed — this is what keeps it contained.

### 4. va_start / va_arg codegen (Track A backend)
- va_start(ap, last): `ap.gp_offset = numNamedGPParams*8; ap.fp_offset = 48 +
  numNamedXMMParams*16; ap.reg_save_area = &save_area; ap.overflow_arg_area =
  rbp+16` (first stack arg).
- va_arg(ap, T):
  - GP T (int/long/ptr/...): if `gp_offset < 48` then `addr = reg_save_area +
    gp_offset; gp_offset += 8` else `addr = overflow_arg_area; overflow += 8`.
    Result `*(T*)addr`.
  - float T (double): same with `fp_offset` (limit 176, step 16) / overflow
    (step 8). Saving XMM unconditionally means %f is CORRECT (no GP-only stub).

### Why not the alternatives (all rejected)
- Library-only stdarg.h: impossible, `va_arg` needs emitted code.
- GP-only shortcut: silently miscompiles `%f` — unacceptable.
- Custom all-on-stack convention: changes the shared call+prologue codegen Pascal
  also uses; higher self-host-gate risk than the additive save-area approach.

### Verification
Self-host byte-identical (changes gated to ProcVariadic). Test a variadic adder /
printf-style consumer == gcc for int/long/ptr/char AND double args, and a va_list
passed into a second function (lua's pattern). Then re-survey lua: lapi/lauxlib/
ldebug/lobject should reach parse-clean (29 -> 33). Linking/amalgamation remains
separate.
