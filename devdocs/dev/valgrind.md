# Valgrind on pxx binaries — the libc-heap profile

pxx binaries are normally static, syscall-only, with their own
arena/freelist allocator (`compiler/builtin/builtinheap.pas`). Valgrind
cannot see into that allocator — memcheck reports "0 allocs, 0 frees"
and every leak is invisible. The `-dPXX_LIBC_HEAP` profile fixes that by
backing the pxx heap with dynamic libc, so memcheck/massif hook every
block with a full call stack.

## Quick start

```sh
# 1. compile with the libc heap + a proc map
./compiler/pascal26 -dPXX_LIBC_HEAP --proc-map prog.npy /tmp/prog

# 2. run under valgrind, symbolize through the map
valgrind --leak-check=full --num-callers=10 /tmp/prog 2>&1 \
    | tools/vgsym.py /tmp/prog.map
```

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

## Symbolizing: `--proc-map` + `tools/vgsym.py`

Valgrind prints raw addresses (pxx ELFs carry no symtab). The compiler's
`--proc-map` flag writes `<out>.map` with one `PROC <hex-addr> <name>`
line per routine; `tools/vgsym.py <map>` is a stdin→stdout filter that
rewrites every `0x...` in the valgrind output to `name+offset`.

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
