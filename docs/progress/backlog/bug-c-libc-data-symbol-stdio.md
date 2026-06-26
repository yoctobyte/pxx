# C: libc data symbols (stdout/stderr/stdin) not imported -> print/IO broken

- **Type:** bug (Track C frontend / ELF dynamic import)
- **Found:** 2026-06-26, getting pxx-compiled lua to RUN.

pxx-compiled lua COMPILES + LINKS (749KB, libc+libm) and RUNS non-IO Lua
(`lua_all -e 'local x=1'` -> rc 0; a script with no output -> rc 0). But any
output crashes: `lua_all -e 'print(1)'` -> SIGSEGV (null deref, si_addr=NULL).

Findings:
- `stdout`/`stderr`/`stdin` are NOT in the executable's dynamic symbols
  (`nm -D` shows none). They are libc DATA symbols (`FILE *`), not functions;
  pxx imports external FUNCTIONS but not DATA objects, so `stdout` reads as 0
  and `fwrite(s,1,n,stdout)` / lua_writestring derefs NULL.
- A bare `fputs("hi", stdout)` C program does NOT crash but prints nothing
  (stdout resolves to a non-null but non-functional value) — so the exact crash
  site in lua's print path needs confirming, but the root is the missing data
  import.

Fix direction: import libc data symbols via a COPY relocation (R_X86_64_COPY) —
reserve BSS space for the object, emit the dynamic reloc so ld.so copies libc's
`stdout` value in at load. Or provide a tiny crt shim that sets stdout/stderr/
stdin from a libc call (e.g. `fdopen`/`__acrt`...) — less clean. This is the
last blocker between "lua compiles+links" and "lua runs print/IO".

Also still open for full lua: bug-c-double-vararg (%f), global ARRAY initializer
data (lua's static luaL_Reg tables; non-array struct/union/scalar already work).
