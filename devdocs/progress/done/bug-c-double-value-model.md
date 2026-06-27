# C `double` value model broken — lua floats all garbage

- **Type:** bug (C frontend float handling — Track A+C)
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27 (Track A+C, the one remaining lua blocker after
  the pxx-compiled interpreter became otherwise functional)

## Symptom

In pxx-compiled lua, **every** floating-point operation yields the same garbage
denormal `3.95e-323` (≈ the bit pattern for the integer 8):

```
print(3.14)        -> 3.95252516673e-323
print(1.5 + 2.5)   -> 3.95252516673e-323
print(2 ^ 10)      -> 3.95252516673e-323
print(7 / 2)       -> 3.95252516673e-323
string.format('%.2f', 3.14159) -> 0.00
math.sqrt(16.0)    -> 3.95252516673e-323
1.5 < 2.5          -> (false / empty)
```

Everything non-float in lua works (control flow, recursion, closures, varargs,
generic-for, string lib, table.sort, metatables + operator overloading,
pcall/error). Float is the sole remaining gap to a complete interpreter.

## What is and isn't broken (probed in isolation, `/tmp/dbl.c`)

The double **value is stored correctly in memory** — reading it back through a
union's `.n`/`.i` field shows the right IEEE bits:

```
double a = 3.14; union { double n; long i; } v; v.n = a;
v.i  ->  0x40091EB851...   (correct bits for 3.14)
```

But the C frontend mishandles doubles as soon as they move through pointer
casts, by-value aggregates, or (suspected) the lua_Number ↔ TValue union and
call/return ABI:

- `*(long*)&dbl` reads **only the low 32 bits** (pointer-cast deref reads int
  width, not the pointed-at 8-byte width).
- A function **returning a struct/union by value that contains a `double`**
  SEGFAULTS.
- All lua float arithmetic/printing produces the same `≈8`-bits denormal, i.e.
  the 8-byte double is being narrowed/boxed through a 4-byte or integer path
  somewhere central (number parse → TValue store, or `luaO_tostr` / `%g` /
  varargs in `print`).

## Likely root area

C-frontend float value model — doubles passing through:
1. **typed-pointer cast + deref width** (`*(T*)p` must load `sizeof(T)`, not int
   width) — same family as the just-fixed `sizeof(*p)` and the `(*p)->field`
   pointer-type bugs;
2. **by-value aggregates containing floats** (struct/union return + arg);
3. the **lua_Number (double) ↔ TValue union** read/write and the
   call/vararg ABI used by `print`/`string.format`.

Ties to the pre-existing float gaps:
- `bug-c-float-int-cast-and-spill` (Single/Double internal-call ABI; float
  spilled/cast through integer regs),
- `%f` / double-vararg formatting (double read as 0 in varargs).

## Fix direction

Get a single C double round-trip green first, in this order (each is a likely
distinct fix):
1. `double d = 3.14; long bits = *(long*)&d;` → full 64-bit (typed-deref load
   width by pointed-at type).
2. `union { double n; long i; }` store/load both directions bit-exact (already
   OK) **and** returned by value from a function (currently segfaults).
3. `double` through a variadic call (`print`-style) read back exact.
Then re-run the lua float chunks (`print(3.14)`, `1.5+2.5`, `%.2f`,
`math.sqrt`) — they should fall out together.

Repro harness: `library_candidates/lua/src/pxx_hostamalg.c` `runchunk` chunks
(build per `BUILD-pxx.md`); standalone `/tmp/dbl.c`. Shared float ABI/codegen →
Track A; gate = `make test` + self-host byte-identical + cross float determinism
guard.

## RESOLVED — 2026-06-27 (Track A+C)

Five distinct fixes; pxx-compiled lua now does floats end to end
(`print(3.14)`, `1.5+2.5`=4.0, `2^10`=1024, `7/2`=3.5, `string.format('%.2f',
3.14159)`=3.14, `math.sqrt(16)`=4.0, float comparisons drive control flow).
Each has a `test/c*_b8N.c` (returns 42) wired into the Makefile C-regression block.

1. **Typed pointer-cast deref load width** (`cparser.inc` CNodePointeeTk): added an
   `AN_PTR_CAST` case reading the cast's type-alias element kind. `*(long*)&d`
   (and `*(double*)p`) had defaulted to tyInteger -> 4-byte load, dropping the
   high 32 bits. Test `cptrcast_deref_double_b81`.
2. **Aggregate (struct/union with double) returned by value** (`cparser.inc`
   sets ProcRetRecId + the hidden aggregate-dest local + LastTypeRecId for a
   tyRecord return; new shared `EmitAggregateDestStash` in `symtab.inc` called by
   both Pascal (`parser.inc`) and C; `ir_codegen.inc` cdecl path loads the hidden
   dest into r10 for an internal aggregate-returning C call). Was a SEGFAULT (the
   Result slot was 0-sized and the dest pointer never stashed). Test
   `caggregate_double_return_b82`.
3. **`va_arg(double)`** (`cparser.inc` picks `__pxx_va_arg_fp` for a float type;
   `lib/crtl/include/stdarg.h` fp helper now reads the FP save area, offset 48
   step 16). The earlier "everything pushed GP" model mismatched the actual SysV
   call+prologue (floats ride XMM -> FP save area). Test `cvararg_double_b83`.
4. **`*(&local) = <double>` store width** (`cparser.inc` CNodePointeeTk AN_ADDR
   case = the operand's own type). lua's `tonumber` macro
   `(1) ? (*(np) = (o)->n, 1) : 0` with `np = &local` truncated to a 4-byte
   store. THIS was the actual `print(3.14)` blocker. Test
   `cderef_addr_local_store_b84`.
5. **C extern binding to a Pascal float routine kept cdecl** (`cparser.inc`: only
   mark `ProcCdecl`/`ProcVariadic`/`ProcNamedGP` when the proc is NEWLY
   C-registered, not when FindProc bound the extern to an existing Pascal proc).
   `sqrt`/`exp`/`sin`/`ln` resolve case-insensitively to the RTL routines; the C
   extern had re-marked them cdecl, so the call passed doubles in XMM while the
   Pascal prologue read them from GP -> `sqrt(16)->0`, `ln(2)->junk`,
   `pow(2,10)=exp(10*ln2)->exp(0)=1`. Test `cfloat_pascal_bridge_b85`.

Gate: `make test` green + self-host byte-identical (all five are front-end /
C-only or byte-identical refactors; the ir_codegen.inc r10 store only fires for a
cdecl aggregate-returning call, of which a Pascal self-build has none).

Out of scope, filed separately:
- `bug-i386-float-byval-param` — pre-existing i386 backend gap (mandelbrot won't
  cross-compile to i386; clean compiler fails identically). x86-64/aarch64/arm32
  float-determinism all green.
- lua `print(true)` / `print(1<2)` render EMPTY — a boolean->string bridge gap,
  independent of floats (the comparison itself is correct: `if 1.5<2.5` works).
