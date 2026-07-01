# Debugging tips for hard compiler/runtime bugs

Most bugs here take 5–10 minutes: read the error, find the code, fix it. This
doc is for the *other* kind — a heisenbug that only shows up during self-host, or
a runtime corruption whose crash site is nowhere near its cause. It's written
from the one that took a full day (`bug-emitasmx64-heap-helpers-oom-selfhost`: a
1-byte codegen fix behind an 8-hour hunt).

The tools below are installed on the dev box. Reach for them roughly in order.

## The golden rule

**Follow the evidence, don't theorize past it.** Every wrong turn in the hard
hunt came from reasoning ("this must be a double-free", "the encoder must be
truncating") instead of measuring. Every step forward came from an instrument
that *reported a fact*. When a theory and a measurement disagree, the theory is
wrong. Reproduce → instrument → read the number → let it point at the next step.

## The compiler is freestanding — plan around it

`pascal26` output is a **static ELF with no libc**: its own `mmap`-backed bump
allocator (`PXXAlloc`/`PXXFree` in `compiler/builtin/builtinheap.pas`, 256 MiB
arenas, a first-fit free list that never unmaps), raw syscalls, and **no
`.symtab`** (function names live only in DWARF when built with `-g`). Two
consequences:

- **valgrind is nearly useless here.** memcheck hooks `malloc`/`free`; it never
  sees `PXXAlloc`'s bump-within-arena, so no per-allocation backtraces and no
  leak records — only the handful of raw 256 MiB `mmap`s. And a *runaway* (live
  infinite-alloc loop) never reaches exit, so leak reporting never runs anyway.
  (If you ever truly need valgrind, you'd have to build a libc-linked variant
  whose allocator is real `malloc` — a project, not a quick hack.)
- **`nm` shows nothing; gdb still resolves names from DWARF.** Build the binary
  under test with `-g` (`./compiler/pascal26 -g compiler.pas /tmp/x`) so gdb and
  `addr2line` can name frames — but note the caveat below about line numbers.

### `-g` line numbers are *flattened*

`compiler.pas` is ~650 physical lines of `{$include}`; the DWARF line table
numbers lines **globally across all includes** (so gdb says
`compiler.pas:50509` for something that's really `ir_codegen.inc`). To map a
reported line back to a file, reproduce the flattening:

```python
# expand {$include ...} depth-first, print line N of the flattened stream
import re, os
inc = re.compile(r'^\s*\{\$(?:include|i)\s+([^\}]+)\}', re.I)
out = []
def expand(p):
    for line in open(p, encoding='latin-1'):
        m = inc.match(line)
        if m and os.path.exists(os.path.join('compiler', m.group(1).strip())):
            expand(os.path.join('compiler', m.group(1).strip())); continue
        out.append(line.rstrip('\n'))
expand('compiler/compiler.pas')
print(out[N-1])   # N = the line gdb reported
```

Keep the flattened file consistent with the binary: **edit source → rebuild `-g`
→ reflatten**, or the numbers drift.

## Reproduce small and cap hard

- **A tiny synthetic `.pas` beats self-hosting `compiler.pas`.** Both faster to
  iterate and far lower risk. The OOM bug reduced to 17 procedures each doing one
  `SetLength` — and later to a ~15-line program (`test_setlength_grow_capacity.pas`).
- **Always cap memory for anything that might run away:** `(ulimit -v 3000000;
  timeout 60 ...)`. This bug OOM-killed the host twice (14 GB RSS) before it was
  caged. A `ulimit -v` turns an OOM into a clean, catchable SIGSEGV.

## Instrument the allocator

When memory misbehaves, make the allocator *narrate*. `builtinheap.pas` is
plain Pascal — add debug prints with raw syscalls (no heap, no libc, safe to call
from inside the allocator):

```pascal
procedure DbgWriteHex(v: Int64);          { write 16 hex digits + \n to fd 2 }
var buf: array[0..16] of Byte; i, nib, dummy: Int64;
begin
  i := 0;
  while i < 16 do begin
    nib := (v shr ((15 - i) * 4)) and 15;
    if nib < 10 then buf[i] := 48 + nib else buf[i] := 87 + nib;
    i := i + 1;
  end;
  buf[16] := 10;
  dummy := __pxxrawsyscall(1, 2, Int64(@buf[0]), 17);   { write(2, buf, 17) }
end;
```

`__pxxrawsyscall(60, code, 0, 0)` is `exit(code)`; a deliberate `PWord(0)^ := 1`
is a clean SIGSEGV you can catch in gdb. High-signal moves that cracked this bug:

- Print the requested `size` each time a **new arena** is mapped → revealed the
  sizes doubled exactly (24M→50M→100M→200M): the fingerprint of a capacity that
  doubles, not linear growth.
- Tag the *callers* (`PXXStrSetLen`, `PXXDynSetLen`, `PXXStrConcat`, …) so you
  learn which path allocates. Here **none** fired for the big sizes → the growth
  came straight from an inline `SetLength` (x86-64 inlines it, bypassing the
  portable helpers), which pointed at codegen, not the runtime library.
- A double-free detector in `PXXFree` (walk the free list, is `addr` already on
  it?) — cheaply *ruled out* a whole class of theory.

## rr — the tool that actually cracked it

Forward gdb kept landing **after** the corruption (a wild write had already
trashed the stack, so backtraces resolved to comments and garbage). `rr` records
once and lets you run **backwards** from the crash to the first cause. This is
the single most valuable tool for corruption-at-a-distance.

Setup (needs perf events; the dev box is configured, resets on reboot):

```
sudo sysctl kernel.perf_event_paranoid=1     # rr needs <= 1
rr record -n /path/to/pascal26-xg args...    # run from the repo root so builtin units resolve
rr replay -d /usr/bin/gdb                    # then drive it with a gdb python script
```

Workhorse moves inside `rr replay` (gdb has full Python; use it):

- **Reconstruct the real call chain** when rbp-unwinding is broken: walk the frame
  pointers by hand — `ret = *(rbp+8)`, `rbp = *rbp` — and `info line *ret` each.
- **`reverse-stepi` out of a runaway** to find the actual loop. Stepping backward
  out of a deep `AppendChar` fault landed squarely in the tight `while i <=
  Length(src)` loop that was the runaway — a loop a forward backtrace couldn't
  reach because the stack was already corrupt.
- **Conditional watchpoint + `reverse-continue`** to find *who wrote* a bad value:
  `watch -l *(long*)ADDR` then `reverse-continue` stops at the writing
  instruction. (Heap addresses are stable under `set disable-randomization on`,
  which rr does by default.)

Reading a managed string at a fault (block layout `[refcount:8][length:8][data]`,
handle = data pointer; allocator size header at `handle-24`):

```python
def rd(a, n=8): return int.from_bytes(gdb.selected_inferior().read_memory(a, n), 'little')
handle = rd(slot)
length   = rd(handle - 8)      # visible length
capacity = rd(handle - 24)     # allocator block size  <-- length==2 but capacity==12MB was the smoking gun
```

The whole hunt turned on one read: a string of **length 2** living in a **12 MB**
block, being asked to grow to 24 MB (= 2× the block). That single fact named the
bug — the inline `SetLength` doubled the *reused block's capacity* instead of the
*length*.

## Self-host lag: a false-positive trap

A change to the compiler's **own codegen** (anything that alters the bytes it
emits for the compiler's own constructs) makes the 2-generation `cmp` in `make
test` (`build` vs `verify`, i.e. gen1 vs gen2) an **unreliable** stability check:
gen1 still runs old-host-emitted code for itself, gen2 runs the new logic, so
gen1 ≠ gen2 is *expected settling*, not a bug. Confirm with a **3rd generation
(gen2 == gen3)**, or seed cleanly:

- **FPC bootstrap sidesteps it.** `make bootstrap` has FPC compile the source to
  a seed compiler whose runtime is native (correct) *and* whose codegen is the
  new logic — so gen1 and gen2 are both fully "new" and converge in the normal
  2-gen `cmp`. Use it whenever a codegen change needs the fix live in the runtime
  before it can validate itself (e.g. a fix for an OOM that would otherwise crash
  gen1 before it can produce gen2). Bootstrapping from FPC for cases like this is
  fine and expected.

## Checklist for a corruption-at-a-distance bug

1. Reproduce with a tiny `.pas`, under `ulimit -v` + `timeout`.
2. Instrument the allocator to narrate sizes/callers; read the numbers.
3. Rule out cheap theories with targeted detectors (double-free, encoding).
4. Build `-g`; when the forward backtrace is garbage, switch to `rr`.
5. `reverse-stepi`/`reverse-continue` from the crash to the first cause.
6. Confirm the fix on the tiny repro; add it as a regression test.
7. If it touches compiler-own codegen: FPC-bootstrap, reseed, then `make test`
   + `stabilize` + `pin`.
