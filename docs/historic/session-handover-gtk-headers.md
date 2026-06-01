# Session Handover: Real System GTK Header Parsing

**Date**: 2026-06-01  
**Goal**: Import GTK functions directly from `/usr/include/gtk-2.0/gtk/gtk.h` — no hand-written wrappers.

---

## What Was Done This Session

### 1. Preprocessor Search Paths Extended (`compiler/cpreproc.inc`)

Added all GTK/GLib include directories to the fallback search chain in `CPInclude()`:
- `/usr/include/gtk-2.0/`
- `/usr/lib/x86_64-linux-gnu/gtk-2.0/include/`
- `/usr/include/glib-2.0/`
- `/usr/lib/x86_64-linux-gnu/glib-2.0/include/` (contains `glibconfig.h`)
- `/usr/include/pango-1.0/`
- `/usr/include/cairo/`
- `/usr/include/gdk-pixbuf-2.0/`
- `/usr/include/atk-1.0/`

### 2. Unit Resolver Extended (`compiler/parser.inc`)

- Added search for `/usr/include/gtk-2.0/gtk/<unitname>.h` as a fallback path
- Added library mapping: `uses gtk` → links against `libgtk-x11-2.0.so.0`

### 3. `test/test_c_gtk.pas` Updated

Changed `uses my_gtk` → `uses gtk` to import the real system header.

### 4. Compiler Limits Increased (`compiler/defs.inc`)

Massively increased all table sizes to handle GTK's large macro/symbol soup:

| Constant | Old | New |
|---|---|---|
| `MAX_CPREP_MACROS` | 1 024 | 65 536 |
| `MAX_CPREP_PARAMS` | 4 096 | 131 072 |
| `MAX_CPREP_CHARS` | 1 MB | 16 MB |
| `MAX_SYMS` | 8 192 | 131 072 |
| `MAX_PROCS` | 512 | 16 384 |
| `MAX_EXTERNAL` | 256 | 16 384 |
| `MAX_TOKENS` | 262 144 | 1 048 576 |
| `MAX_CTYPEDEF` | 512 | 16 384 |
| `MAX_ENUMTYPE` | 64 | 1 024 |
| `MAX_ENUMVAL` | 512 | 8 192 |
| `STRING_CAP` | 1 MB | 16 MB |

---

## Where We Got Stuck

After increasing the limits, `make` (self-hosted fixedpoint build) **failed** with:

```
ok: /tmp/pascal26-verify  [code=646785B  data=26400B  bss=-802870988B  procs=367]
cmp /tmp/pascal26-build /tmp/pascal26-verify
/tmp/pascal26-build /tmp/pascal26-verify differ: byte 105, line 2
```

The **BSS size overflowed** (negative value = 32-bit signed overflow in the BSS size calculation). The combined size of all the enlarged static arrays now exceeds ~2 GB, which the current ELF emitter or fixedpoint comparison cannot handle.

The `test/test_c_gtk.pas` was not yet successfully compiled with the real `gtk.h` — the previous attempt (before limit increase) hit `too many C macros`.

---

## What Needs to Happen Next

### Option A: Fix the BSS overflow (Recommended)

The root issue is that all compiler state is in global BSS arrays. With 16 MB of preprocessor chars, 131K symbols, 1M tokens etc., the total static BSS exceeds 2 GB.

**Solutions (in order of preference):**
1. **Reduce limits more conservatively** — find the real minimum needed for GTK headers (count macros/typedefs at runtime, pick a safe headroom). Something like 8K macros, 4M chars, 32K syms probably suffices.
2. **Heap-allocate the biggest arrays** — `CPrepChars`, `Tokens`, `TokChars`, `Syms`, `Procs` could be dynamically allocated at startup with `GetMem`. The symtab hardcodes array layout so this requires care.
3. **Don't need all limits large** — many limits (MAX_IR, MAX_AST, MAX_UCLASS etc.) don't need to grow; only the C preprocessor and symbol tables do.

### Suggested Conservative Limits

Try these first (should stay well under 2 GB BSS):

| Constant | Suggested |
|---|---|
| `MAX_CPREP_MACROS` | 8 192 |
| `MAX_CPREP_PARAMS` | 32 768 |
| `MAX_CPREP_CHARS` | 8 388 608 (8 MB) |
| `MAX_SYMS` | 32 768 |
| `MAX_PROCS` | 4 096 |
| `MAX_EXTERNAL` | 4 096 |
| `MAX_TOKENS` | 524 288 |
| `MAX_CTYPEDEF` | 8 192 |
| `MAX_ENUMTYPE` | 512 |
| `MAX_ENUMVAL` | 4 096 |
| `STRING_CAP` | 8 388 608 (8 MB) |
| `MAX_CALLFIX` | 16 384 |
| `MAX_GLOBFIX` | 32 768 |
| `MAX_DATA` | 2 097 152 (2 MB) |
| `MAX_STRS` | 8 192 |
| `MAX_FIXUPS` | 131 072 |

> [!IMPORTANT]
> After adjusting limits, do a full `make` (self-hosted fixedpoint), confirm BSS is positive and the two binaries are identical (cmp passes). Only then proceed.

### After the BSS Fix

Once `make` passes with increased limits:

1. **Run**: `./compiler/pascal26 test/test_c_gtk.pas /tmp/test_c_gtk26`
   - Expect a different error (likely a C parser issue, not a limit overflow)
   - Common GTK header problems: `__attribute__((…))` on struct members, `__extension__`, varargs `...`, anonymous structs/unions, `#pragma once`

2. **Fix parser errors** in `compiler/cparser.inc` and `compiler/cpreproc.inc` as they appear. Common GTK-header parser gaps:
   - `struct { ... };` anonymous struct/union inside typedef → skip body
   - Attribute syntax `__attribute__((…))` on declarations → already partially handled, may need extension for struct member attributes
   - `volatile` / `restrict` qualifiers → treat like `const` (skip)
   - Varargs `...` in parameter lists → stop parsing params there

3. **Update `Makefile`**: change the `test_c_gtk` target to check for a higher count of parsed symbols from `gtk.h`, not `my_gtk.h`.

4. **Update `lib/lcl/gtk3.pas`**: change `uses gtk3_c` to `uses gtk` so the entire LCL layer imports from real system headers.

5. **Run `make test`** to confirm all existing tests still pass.

---

## System Info

- GTK version: **GTK 2** only (`/usr/include/gtk-2.0/gtk/gtk.h`)
- GTK3 not installed (`pkg-config --cflags gtk+-3.0` → not found)
- Runtime library: `libgtk-x11-2.0.so.0`
- GLib runtime: at `/usr/lib/x86_64-linux-gnu/glib-2.0/include/glibconfig.h`
- GDK config: at `/usr/lib/x86_64-linux-gnu/gtk-2.0/include/gdkconfig.h`

## Key Files

| File | Role |
|---|---|
| [cpreproc.inc](file:///home/rene/frankonpiler/compiler/cpreproc.inc) | C preprocessor, search paths at `CPInclude()` ~line 720 |
| [cparser.inc](file:///home/rene/frankonpiler/compiler/cparser.inc) | C parser, `ParseCUnit`, `ParseCTypedef`, `ParseCSubroutine` |
| [defs.inc](file:///home/rene/frankonpiler/compiler/defs.inc) | All limits at top, BSS arrays throughout |
| [parser.inc](file:///home/rene/frankonpiler/compiler/parser.inc) | Unit resolution ~line 5266, library mapping ~line 5287 |
| [gtk3.pas](file:///home/rene/frankonpiler/lib/lcl/gtk3.pas) | Pascal LCL helper layer; currently `uses gtk3_c` |
| [test_c_gtk.pas](file:///home/rene/frankonpiler/test/test_c_gtk.pas) | Now `uses gtk` (real header) |
