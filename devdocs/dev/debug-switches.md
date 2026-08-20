# Debug switches — `-dPXX_HEAP_DEBUG`, `-dPXX_OBJTRACE`, `PXXDBG=`

Three independent switches, all off by default. The first two are compile-time
defines affecting the emitted PROGRAM; the third is an environment variable
read by the COMPILER. See also `devdocs/dev/dwarf.md` for gdb.

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

# 3. Compiler-side topics — `PXXDBG=`

```sh
PXXDBG=help              compiler/pascal26 prog.py out   # where to look
PXXDBG=n.locals          compiler/pascal26 prog.py out
PXXDBG=n.locals,n.ctorargs compiler/pascal26 prog.py out
PXXDBG=n.*               compiler/pascal26 prog.py out   # a whole lane
PXXDBG=all               compiler/pascal26 prog.py out
```

## Topics

**This table is the authority.** The compiler does NOT carry a hardcoded topic
list — `PXXDBG=help` just points here. A list duplicated in source drifts, and a
drifted list is worse than none.

Topics are namespaced by owning lane, using the track letters from CLAUDE.md, so
a frontend can add a probe without colliding with another's. A trailing `.*`
enables a whole lane.

| topic | lane | what it prints |
| --- | --- | --- |
| `n.locals` | N (NilPy) | the inferred local table per routine, after the inference fixed point — "what type did NilPy actually give this local" |
| `n.ctorargs` | N (NilPy) | every NilPy construction's argument AST kind + type kind |
| `a.ir:<proc>` | A (core) | the IR of ONE routine (`a.ir:*` = `--dump-ir`) |
| `a.ast:<proc>` | A (core) | that routine's AST tree before lowering |
| `a.inline` | A (core) | one line per routine whose body is RETAINED for inline expansion: name, body shape (1 = `Result := E`, 2 = if/else ternary, 3 = straight-line), param count, and whether the body contains a call / reads a global |
| `a.reload:*` | A (core) | one line per load the -O3 store->reload pass MARKED redundant: IR node, sym index, sym name. The firing count is what a test asserts — an -O0-vs-O3 differential that passes because the pass never ran asserts nothing |
| `a.arc:<proc>` | A (core) | every symbol the scope-exit managed-cleanup pass CONSIDERS for that routine, with the three facts that decide whether it is released: `kind` (only `skLocal` is released), `comIntf`, `hiddenArgTemp` — plus `scopeBase`/`symCount`/`retSym`. The epilogue releases are emitted as MACHINE CODE, not IR, so a leaking managed temp is invisible in `a.ir`; without this the only way to tell a skipped temp from a released one was to disassemble. It is what showed that the by-value interface temp was NOT skipped by this pass, killing a plausible wrong root cause |
| `n.*` / `a.*` | — | everything in a lane |
| `all` | — | everything |

A topic ending in `:<name>` takes an argument — the routine to dump. That is the
difference between 19 lines and 83,046: `--dump-ir` dumps every body in the
program, `a.ir:combine` dumps the one you asked about.

`a.inline` answers the question an -O3 miscompile actually poses. Bisecting by
flipping `OptLevel < 3` gates tells you which SLICE is responsible and never
which ROUTINE, and the wrong routine is where an -O3 hunt goes to die: the only
evidence is a plausible wrong value somewhere else entirely. Listing what was
retained, with `hasCall` marking the bodies whose arguments must be
temp-captured, turned
`bug-a-o3-inline-retention-substitutes-a-global-read-across-a-call` from a
theory about globals into an 11-line repro — the retained list showed the
`__pxx_*` PAL shims, and the C program under test called one with a string
literal.

`a.ast` is STRUCTURAL, not pretty-printed — kind and type-kind are numbers.
There are 127 `AN_` constants and no name table; adding one would be a second
list to keep in step, which is the drift this file exists to avoid. Read the
`AN_` constants in `defs.inc` alongside it.

Adding a topic: pick `<lane>.<name>`, call `PxxDbgEnabled('<lane>.<name>')` at
the probe, and add the row above. There is nothing else to update.

Why namespaced at all: the first two topics were `locals` and `ctorargs`, flat.
The moment Track C wants "dump the local table" that name is taken, and
`PXXDBG=locals` printing nothing tells you neither "wrong topic" nor "no NilPy
routine was compiled". A lane prefix makes a typo visible.

**Why it exists.** Until 2026-07-29 there was no `GetEnv` anywhere in the
compiler, so every parser/typing probe cost edit-source + a ~90s self-compile +
remembering to strip it. That round trip is why a wrong root-cause premise ended
up recorded in `bug-nilpy-slice-of-variant-local-returned-is-unusable`: the
cheap move was to reason rather than measure. Both topics above are probes that
were hand-patched in during that hunt; `ctorargs` is the one that eventually
disproved the premise.

Notes:

- Matching is on comma-separated TOKENS, not a raw substring — a substring test
  would make `locals` silently match a future `modulelocals`.
- Read once from `/proc/self/environ` via the `sysopen`/`sysread`/`sysclose`
  intrinsics, so one implementation serves the FPC-bootstrap and self-hosted
  builds.
- With `PXXDBG` unset the emitted output is byte-identical (verified for a
  NilPy and a Pascal program) and the self-host fixedpoint holds.

# 4. Debugging the COMPILER itself — `make pxx-debug`

```sh
make pxx-debug
gdb --args compiler/pascal26-debug prog.py /tmp/out
(gdb) break PyClassCreate
(gdb) bt
```

Written to `compiler/pascal26-debug`, a SEPARATE path: `compiler/pascal26` and
the pinned stable are untouched, so a debug session cannot contaminate a gate
run or the binary other tracks build on.

**Function-level only.** `break <routine>`, backtraces, `info args`/`locals`
work. Line numbers do NOT: `ExpandIncludes` splices every `.inc` into one buffer
and the lexer numbers lines in that, so `info line IRDump` says
`compiler.pas:61871` for a 1001-line file. Same bug as C had one layer up —
see `bug-compiler-selfdebug-lines-index-expanded-source`, which carries the fix
shape (the C one is done and most of it is reusable).

## Related

- `devdocs/progress/backlog/feature-heap-poison-and-object-trace.md` — this
  plus the retain/release trace still to come.
- `devdocs/progress/backlog/feature-debuggability-umbrella.md` — where this sits
  relative to the compiler-side `PXXDBG` switch, real DWARF, and the CPython
  differential harness.
