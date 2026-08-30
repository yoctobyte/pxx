# Valgrind on pxx binaries — the libc-heap profile

pxx binaries are normally static, syscall-only, with their own
arena/freelist allocator (`compiler/builtin/builtinheap.pas`). Valgrind
cannot see into that allocator — memcheck reports "0 allocs, 0 frees"
and every leak is invisible. The `-dPXX_LIBC_HEAP` profile fixes that by
backing the pxx heap with dynamic libc, so memcheck/massif hook every
block with a full call stack.

## Quick start

```sh
# 1. compile with the libc heap. The <out>.map file is written BY DEFAULT
#    (--no-map suppresses it); no extra flag is needed.
./compiler/pascal26 -dPXX_LIBC_HEAP prog.npy /tmp/prog

# 2. run under valgrind, symbolize through the map
valgrind --leak-check=full --num-callers=10 /tmp/prog 2>&1 \
    | tools/vgsym.py /tmp/prog.map
```

> **Corrected 2026-08-30 (frankD).** Step 1 used to pass `--proc-map`, and the
> prose below used to say that flag is what writes `<out>.map`. Both wrong, and
> the second one dangerously: **`--proc-map` writes to stderr, and for a DYNAMIC
> build its addresses are 0x70 too low** — see "Do not use `--proc-map` here"
> below. The pipeline above was always right; it reads the `.map` file, which
> `--proc-map` never wrote and which you get without asking.

Works for any frontend (`.pas`, `.npy`, `.c`, ...). The output looks like:

```
10,192 bytes in 259 blocks are definitely lost in loss record 737 of 782
   at calloc (vgpreload_memcheck)
   by 0x4004BC PXXAlloc+0xc9
   by 0x4007C6 PXXStrFromLit+0x85
   by 0x400263 _start+0x17b          <- an emitted runtime blob, see below
   by 0x44EE0E PyHostCall+0x368
   by 0x4A2FD3 ParseCall+0x187
```

## What `-dPXX_LIBC_HEAP` does

`builtinheap.pas` has three heap profiles selected by define (same
pattern as `PXX_ESP_IDF`):

- default: mmap arenas + size-class freelists (production).
- `PXX_ESP_IDF`: calloc/free resolved at IDF link time.
- `PXX_LIBC_HEAP`: `calloc`/`free` imported from `libc.so.6` via the
  ordinary `external 'lib' name 'sym'` machinery. Declaring the externals
  is what flips the ELF writer into dynamic mode (PT_INTERP +
  DT_NEEDED + PLT) — no extra flag needed.

Contracts preserved: calloc keeps PXXAlloc's zero-init guarantee; the
same 8-byte size header keeps PXXRealloc's copy length; HeapLow/HeapHigh
become a coarse min/max envelope over all libc blocks so PXXObjPlausible
(the object-ARC guard) keeps working.

NOT for production or benchmarks: no size-class bins, libc's lock
discipline instead of the pxx one, and RSS behaves differently (libc
returns memory to the OS; the arena allocator does not).

## Symbolizing: `<out>.map` + `tools/vgsym.py`

Valgrind prints raw addresses (pxx ELFs carry no symtab). The compiler writes
`<out>.map` alongside every binary unless you pass `--no-map`
(`compiler.pas`, `grep -n 'EmitMapFile'`), one `0x<16-hex-addr> <name>` line per
routine; `tools/vgsym.py <map>` is a stdin→stdout filter that rewrites every
`0x...` in the valgrind output to `name+offset`. It accepts both that format and
the `PROC <addr> <name>` one, which is why the wrong input below produced wrong
answers instead of an error.

### Do not use `--proc-map` here — it is 0x70 low on exactly this profile

`--proc-map` is a *profiler* flag: it prints `PROC <addr> <name>` to **stderr**,
computing each address as `LOAD_ADDR + CODE_OFFSET + BodyAddr`, and
`compiler.pas` says so in its own comment — *"x86-64 static layout only … a
dynamic build shifts by the dynamic header delta."*

`-dPXX_LIBC_HEAP` **is** a dynamic build. That is the whole point of the profile:
declaring the libc externals flips the ELF writer into dynamic mode, so the code
sits at `DYNAMIC_CODE_OFFSET` (0x120), not `CODE_OFFSET` (0xb0)
(`defs.inc:1323` and `:1432`, both by grep for the names). Measured on the pinned
binary, one routine, one program compiled twice:

| build | `<out>.map` | `--proc-map` on stderr |
| --- | --- | --- |
| default (static) | `0x40efb0 Foo` | `0040efb0 Foo` — agree |
| `-dPXX_LIBC_HEAP` (dynamic) | `0x40eb61 Foo` | `0040eaf1 Foo` — **0x70 low** |

0x70 is exactly `DYNAMIC_CODE_OFFSET - CODE_OFFSET`, so the error is a constant
shift over every routine, not noise.

**It does not fail; it lies.** `vgsym.py` resolves with `bisect_right - 1` and a
0x20000 tolerance, so a shifted address still matches *something* — the routine
before the right one, whenever 0x70 crosses a boundary. Most routines are shorter
than 0x70.

The two caveats below about the emitted blobs were recorded against `--proc-map`
output and should be re-read with that in mind: the blobs begin at 0x400120 in a
dynamic build, and a uniform 0x70 under-shift pushes the first of them back into
`_start`'s range — which is precisely the reported symptom. Whether anything is
left of them once you symbolize through `<out>.map` has **not** been measured
here (valgrind is not installed on this box, so this correction is from the
compiler's output, not from a run). Track A ticket for the flag itself:
[[bug-a-proc-map-emits-static-addresses-for-a-dynamic-build]].

Caveats:
- Addresses inside the emitted runtime blobs (AnsiStr*/obj retain/release
  shims, low addresses ~0x400100–0x400800) symbolize as `_start+...` —
  read them as "an emitted string/ARC helper" and look one frame further
  down for the real caller.
- The blobs don't push frame pointers, so a stack can skip a frame or
  carry one garbage entry. `--num-callers=10` or more gives enough
  context around it.
- `+0x...` offsets are from the routine's start; there is no line-level
  mapping.

## Recipes

Leak hunt (what it's for):

```sh
valgrind --leak-check=full --num-callers=10 ./prog 2>&1 | tools/vgsym.py prog.map
```

Aggregate a big report by call-site signature (the pattern used during
the object-reclamation night — see bug-n-pyeval-per-exec-leaks for a
worked example): group "definitely lost" records by frames 2–4 and sum
bytes; a dozen lines of python collapses hundreds of records into a
ranked table.

Corruption hunt (invalid read/write, use-after-free):

```sh
valgrind --num-callers=12 ./prog 2>&1 | tools/vgsym.py prog.map
```

memcheck's freed-block tracking only knows blocks that went through
libc, i.e. all of them under this profile — so UAF on heap blocks is
caught precisely. Stack corruption is NOT better than before (valgrind
doesn't track pxx frames).

Heap profiling over time:

```sh
valgrind --tool=massif ./prog && ms_print massif.out.<pid>
```

Massif snapshots attribute growth to PXXAlloc call sites — useful when
RSS grows but nothing is "lost" (still-reachable growth, e.g. a registry
that never shrinks).

## Interpreting results

- "definitely lost" = a real leak: no pointer to the block anywhere.
- "still reachable" at exit is usually fine (globals, caches, interned
  data); pxx programs never free at exit by design.
- "possibly lost" often points INTO a block (a pxx managed-string handle
  is base+16 of its heap block, an object header likewise) — valgrind
  sees an interior pointer and hedges. Treat sustained growth there as
  real; one-off entries as noise.
- ERROR SUMMARY 0 + leaks = pure lifetime bugs (refcount never reaches
  zero); errors > 0 = look at the FIRST invalid read/write before
  trusting any later report.

## Keep the sides honest

- Shrink iteration counts first: 200 loop iterations under valgrind
  beats 20k in wall-clock and the leak totals scale linearly anyway.
- The native and libc heaps can behave differently around the emitted
  x86-64 fast paths ONLY in timing, not in protocol — a leak seen under
  `PXX_LIBC_HEAP` is real in the native heap too, and vice versa.
- The RSS numbers `make bench-uforth` tracks come from the NATIVE
  allocator; never compare them against libc-profile runs.
