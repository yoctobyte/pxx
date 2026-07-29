# Debug heap and object trace — `-dPXX_HEAP_DEBUG`, `-dPXX_OBJTRACE`

Two independent compile-time switches. They compose; both are off by default
and neither changes the shipped binary.

# 1. The debug heap — `-dPXX_HEAP_DEBUG`

Compile any program (Pascal, NilPy, C — it is the shared allocator) with

```sh
compiler/pascal26 -dPXX_HEAP_DEBUG prog.py out
./out
```

and freed memory becomes **poison** (`$DD` bytes) that is held out of the free
list for the next 1024 frees instead of being handed straight back out.

## Why

Every ownership bug in this runtime presents as a **plausible value**, never as
a fault. `PXXAlloc` zeroes a block on reuse, so a read through a dangling
pointer sees either zeros or whatever the block's new owner wrote. The worked
example is `bug-nilpy-slice-of-variant-local-returned-is-unusable`, where a
freed `TPyList`'s header words had been recycled into a string and

```
len(self.evidence) == 1751084129
```

Nothing in that number says "freed". It cost three sessions and two wrong
root-cause premises. With the flag the same run reads

```
evidence len= -572662307        # 0xDDDDDDDD
```

which is unmistakable, at the point of the read rather than far away.

## What it detects

| report | meaning |
| --- | --- |
| the value itself reads as `0xDDDD…` / `-572662307` / `-2459565876494606883` | a **read** through a dangling pointer |
| `pxx-heap: DOUBLE FREE of 0x…` | the block was already in quarantine |
| `pxx-heap: WRITE AFTER FREE in 0x…` | poison was modified while quarantined (found when it is evicted, so up to 1024 frees late) |
| `pxx-heap: RETAIN of a FREED object 0x…` | `PXXObjRetain` on a quarantined object — a NilPy refcount bug |
| `pxx-heap: RELEASE of a FREED object 0x…` | the same on `PXXObjRelease` (double release) |

Reports go to **stderr**, one line each, address in fixed-width hex so they
grep and sort.

## Guarantees and limits

- **Off by default, and the default build is byte-identical.** Everything is
  inside `{$ifdef PXX_HEAP_DEBUG}`, and the free-list push is kept INLINE in
  `PXXFree` for the default build rather than factored into `PXXFreePush` —
  a call per free is not worth paying for a facility that is off. Verified:
  self-compiling the compiler with these changes reproduces the previous binary
  bit for bit.
- Quarantine is **1024 blocks** (`HEAP_QUAR_MAX`, 8 KiB of BSS). A dangling
  read that happens more than 1024 frees after the free can still land on a
  recycled block. Raise the constant for a long-running repro.
- Write-after-free is reported when the block leaves quarantine, so the report
  is **late** — it names the block, not the writer. Pair it with a narrowing
  bisect, or lower `HEAP_QUAR_MAX` to tighten the window.
- Implemented for the **native** allocator only. The ESP static-arena build and
  the `PXX_LIBC_HEAP` build (which routes through libc `calloc`/`free` so
  valgrind can see allocations) are untouched.
- Poison is `$DD` on purpose: non-zero, non-ASCII, and the same byte in every
  position, so it is recognisable however it is misread — as an integer, a
  pointer, a length, or a float.

# 2. The object trace — `-dPXX_OBJTRACE`

```sh
compiler/pascal26 -dPXX_OBJTRACE prog.py out
./out 2>trace.log
```

One line per refcount event on stderr:

```
objtrace A 0x000070a88de00018 1      # allocated, rc = 1
objtrace R 0x000070a88de00018 2      # retained
objtrace r 0x000070a88de00018 1      # released
objtrace F 0x000070a88de00018 0      # rc hit 0, about to be freed
```

`grep 0x000070a88de00018 trace.log` gives one object's whole life, in order.

**Why it exists:** every bug in the NilPy object-reclamation family is the same
question — *who took a reference and who dropped it* — and it is normally
answered by inferring backwards from a corrupted value. This answers it by
reading. The trace above is from a three-line program and already shows the
current model plainly: two retains, no release, so a class slot holds the last
reference forever (class slots are never released — which is exactly why the
missing retain in `pyvarobj` was fatal while an unretained *list local* merely
leaked).

Notes:

- **Allocation-free by construction.** The line is built in a local byte buffer
  from character constants and emitted with one raw write. A trace that
  allocated would perturb the heap it reports on and would re-enter the
  allocator from inside `PXXObjRelease` -> `PXXFree`.
- No filtering: a real app emits a lot. Redirect stderr and grep. If volume
  becomes the problem, add the filter at the point of need rather than a
  general mechanism.
- Covers `PXXObj*` refcounting only — headered NilPy objects. Managed
  AnsiString handles use `PXXStrIncRef`/`DecRef` and are not traced yet.

## Using the two together

`-dPXX_HEAP_DEBUG -dPXX_OBJTRACE` is the combination for an ownership bug:
the trace shows the release that should not have happened, and the poison shows
where the freed block is subsequently read. Start with poison (it tells you
there IS a use-after-free and which read hits it), then add the trace (it tells
you which release caused it).

## Related

- `devdocs/progress/backlog/feature-heap-poison-and-object-trace.md` — this
  plus the retain/release trace still to come.
- `devdocs/progress/backlog/feature-debuggability-umbrella.md` — where this sits
  relative to the compiler-side `PXXDBG` switch, real DWARF, and the CPython
  differential harness.
