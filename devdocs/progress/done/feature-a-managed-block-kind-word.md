---
track: A
prio: 60
type: feature
summary: "Phase 1 of multi-type strings: add an 8-byte kind word below the refcount in the shared managed-block header (strings, dynarrays, objects), write zero, never read it. Prove nothing regressed, then pin — phase 2 depends on the pin"
status: done
owner: claude-A-N
---

# Managed-block header: add the kind word (phase 1, layout only)

- **Type:** feature (ABI/layout) — **Track A**
- **Design:** `devdocs/dev/managed-block-header.md` — read it first, the layout
  and the three migration rules are decided there.
- Unblocks: [[feature-nilpy-text-string-kind]] (phase 2).

## ⚠ This cannot be built with `make compiler/pascal26`

**Seed from FPC.** A header-offset change cannot pass through a self-host
generation: stage A emits stage B's inline string code with *A's* offsets while
B's linked RTL uses the new layout, so B is internally inconsistent and dies
before it can compile C. Same family as the `TSymbol`-field bootstrap landmine.
`make compiler/pascal26` will fail in a way that looks like a codegen bug and is
not.

## Scope — layout ONLY

Move the layout, allocate the word, write **zero**, and read it nowhere. No
kinds, no semantics, no behaviour change. Success is "byte-identical behaviour,
8 more bytes per block". Phase 2 does not start until this is pinned.

Add a magic in the word under `-dPXX_HEAP_DEBUG` and assert it on free. The
failure mode here is a free at the wrong base, which corrupts the allocator and
surfaces arbitrarily far from the cause; the magic turns that into an immediate,
located failure. Without it, phase 1 can *appear* to work.

## The change

```
before                          after
[alloc size:8]  B-8             [alloc size:8]  B-8
[refcount:8]    B+0             [kind:8]        B+0     NEW, zero
[length:8]      B+8             [refcount:8]    B+8
[data...]       B+16 = p        [length:8]      B+16
                                [data...]       B+24 = p
```

From the handle `p`: **`length` stays at `p-8`, `refcount` stays at `p-16`.**
Only the block base moves, `p-16` → `p-24`. That is the point of this placement —
the ~73 length reads and every retain/release blob across six backends are
untouched.

## The trap: two visually identical `-16`s with opposite fates

`base := Int64(p) - 16` is used today for **both** the refcount address and the
free base, because they are the same address. They diverge now:

- used as a **block/free base** → becomes `- 24`
- used to **read or write the refcount** → stays `- 16`

Surveyed sites in `compiler/builtin/builtinheap.pas`:

| line | today | fate |
| --- | --- | --- |
| 838 | `block := Int64(arrData) - 16` *(block base)* | **−24** |
| 1385, 1399 | `base := Int64(p) - 16` (`PXXStrIncRef`/`DecRef`) | **split** — rc at −16, free at −24 |
| 1545, 1580, 1892 | `base := Int64(p) - 16` | **−24** (verify each) |
| 1908 | `base := Int64(arrData) - 16` | **−24** |
| 1843 | `rc := PWord(oldHandle - 16)^` *(refcount read)* | **stays −16** |
| 2246 | `refCountPtr := PWord(Int64(arrData) - 16)` | **stays −16** |
| 2165, 2189 | `[VMT-16]` layout descriptor | **unrelated** — class blob, not this header |

Allocation sites (all become +8 / data at `base + 24`):
`858` (`PXXAlloc(16 + newLen*elSize)`), `861`, `900`/`903`, `942`/`945`,
`1359`/`1362`, `1486`/`1489`, `1499`/`1502`, `1528`/`1531`. The `+ 17` forms are
16 header + 1 NUL → become `+ 25`.

`PXXObjAlloc` (1483–1492) has **three** constants that all move, and the middle
one is the dangerous one:

```pascal
base := Int64(PXXAlloc(size + 16, 8));   { → + 24 }
PWord(base)^ := 1;                       { refcount → base + 8 }
PWord(base + 8)^ := PXX_OBJ_MAGIC;       { → base + 16 — TODAY'S base+8 IS THE NEW REFCOUNT }
Result := Pointer(base + 16);            { → base + 24 }
```

Leave the magic where it lands relative to the handle (`p-8`, the object spare
slot); phase 2 retires it in favour of `kind = Object`.

**`PWord` here is a pointer to a MACHINE WORD, not FPC's 2-byte `PWord`.** Anyone
editing these lines with FPC's meaning in mind writes 2 bytes where 8 are needed.
The trap is sitting in the routine this phase has to change.

## Emitters

Each backend hardcodes the free base in its release blobs. x86-64
`EmitAnsiStrReleaseLocked` (`ir_codegen.inc:127`) is the pattern:

```
dec qword [rax-16]     { refcount — STAYS }
sub rax, 16            { free base — becomes 24 }
```

Same for `EmitDynArrayReleaseLocked` and the object release path, times six
backends (`ir_codegen.inc`, `386`, `aarch64`, `arm32`, `riscv32`, `xtensa`).
Also the inline allocation sequences that write the refcount at the block base
(`ir_codegen.inc:5168`, `5726`: `mov qword [rax],1 (refcount)`) — refcount moves
to `base+8`, data to `base+24`.

## Gate — this is the documented exception that justifies widening

The per-fix loop (quick + fixedpoint) is **not** sufficient here: a wrong offset
is silent heap corruption, not a red test, and the offsets are copied across six
hand-written emitters. Ticket-specific justification to run the full tier.

1. **FPC seed build green** — the only way in.
2. self-host fixedpoint byte-identical.
3. `tools/testmgr.py --tier full` — all six targets.
4. the object-reclamation, dynarray and RTTI suites specifically.
5. a `-dPXX_HEAP_DEBUG` run, for the free-base magic.
6. frozen/inline and ESP paths confirmed unaffected (they carry no header, so
   this should be a provable no-op).

Then `make stabilize` → `make pin` → commit `stable_linux_amd64/**` with the
source change.

## Do not park this half-applied

A half-applied header change breaks every consumer at once. If it cannot be
landed green, **revert the working tree** and leave the survey above for the next
session — do not leave it in `unfinished/`.

## 2026-08-07 — implementation record

### The emitter sweep was x86-64 ONLY

The ticket assumed six hand-written emitters each carrying the free base. They
do not. The five cross backends (`386`, `aarch64`, `arm32`, `riscv32`,
`xtensa`) use `EmitHeapFreeLocked*` **only for the `FreeMem` intrinsic** — a
raw user pointer, not a managed handle — and delegate managed
retain/release to the Pascal routines in `builtinheap.pas`. aarch64 has no
inline refcount blob at all. So the entire emitter change is two release blobs
and two inline allocation paths in `ir_codegen.inc`. Large de-risking, and worth
knowing before the next header change.

### A THIRD header-relative constant the survey missed

The AnsiString in-place resize fast path reads the **allocator's own capacity
word** to decide whether a buffer can grow without reallocating:

```
cmp rax, [rsi-24]     { capacity payload }
```

That word belongs to the allocator and sits 8 bytes below *our* block base — so
it moves with our header, `[rsi-24]` → `[rsi-32]`. Missing it would have left
`SetLength` believing every block was 8 bytes larger than it is: an in-place
grow that overruns into the next block, silently. It is not a refcount and not a
length, which is why it was not in either category the survey enumerated.

The same routine also adds `17` (16 header + nul) twice for the needed payload →
`25`.

### What was built

- **Named offsets** (`PXX_HDR_SIZE/_KIND/_RC/_LEN`, `PXX_KIND_LEGACY`) replace
  every literal in `builtinheap.pas`, so the next layout move is one edit rather
  than another survey.
- **`PXXHdrBase(p)` and `PXXHdrRC(p)`** split the two meanings the old
  `base := Int64(p) - 16` carried. Every free now goes through `PXXHdrBase`;
  every refcount access through `PXXHdrRC`. The variable is renamed `rcAddr`
  wherever it was really the refcount, because the misleading name is what would
  cause the next bug.
- **Debug witness**: `PXXHdrInit` stamps `PXX_HDR_MAGIC` under
  `-dPXX_HEAP_DEBUG`, and `PXXHdrBase` halts (204) if a computed base does not
  carry it. It accepts `PXX_KIND_LEGACY` as well, because the x86-64 **inline**
  allocation paths lay the header down in emitted code and cannot see the
  define. A wild base is still caught — freed memory is `$DD` poison and live
  neighbours are lengths or payload.
- Plain `GetMem` / Pascal class instantiation is **unheadered** (the instance
  pointer IS the allocator payload, VMT at offset 0) and is correctly untouched;
  that is the population `PXX_OBJ_MAGIC` discriminates.

### Verified

- **FPC seed bootstrap reached fixedpoint** — gen1 and gen2 byte-identical
  (`cmp` passed). This is the proof that matters; `gate.sh`'s own fixedpoint
  seeds from the PINNED (old-layout) binary and **cannot** validate this change.
- Pascal smoke: concat, a 200-iteration growth loop (exercises the inline
  resize + COW + capacity paths), `SetLength` regrow preserving the prefix and
  zeroing the tail, `array of AnsiString`, empty strings.
- NilPy: 50 refcounted objects, 100-entry dict of lists, 300-iteration string
  growth, comprehensions — output identical to CPython.
- RTTI-driven class finalization: 300 create/free cycles of a class with two
  managed string fields and a dynarray field, releasing via the layout
  descriptor. Clean.
- All of the above **also under `-dPXX_HEAP_DEBUG`** — no false positives from
  the magic check, which means every free base is being computed correctly.
- All six backends compile. xtensa needs `--platform=esp --esp-profile=bare`;
  its failure on a plain `WriteLn` program is **pre-existing** (identical on the
  pinned binary — controlled, not assumed).

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.
