---
track: A
prio: 45
type: bug
---

# Managed-string arg-materialization temp leaks one handle per loop iteration

A frozen literal (or any materialized value) passed to a `const s:
AnsiString` / `const string` parameter is bound to a hidden owning temp
in IRLowerCallArg (7 sites, all `argIsManagedTemp` → `hiddenArgSym`):

```
IRAppend(IR_DEFAULT_MEM, <slotaddr>, ..., tyAnsiString);  { zero the slot }
IRAppend(IR_STORE_SYM, hiddenArgSym, value, ...);          { materialize + store }
```

The `IR_DEFAULT_MEM` zeroes the slot (plain `rep stosb` for a non-record
tyAnsiString — it does NOT release), so on every loop iteration it drops
the previous iteration's handle before the STORE's release-old can free
it. `mk('x')` in a 20k loop leaks 20k blocks (~640 KB); the same pattern
inside pyeval's PyHostCall/PyFindMethCI was the top per-exec leak the
valgrind libc-heap profile attributed to `PXXStrFromLit <- PyHostCall`.

## Reproduce

```pascal
function mk(const s: AnsiString): AnsiString; begin Result := s + '!'; end;
var i: Integer; m: AnsiString;
begin for i := 1 to 20000 do m := mk('x'); end.
```

`pascal26 -dPXX_LIBC_HEAP prog.pas out; valgrind --leak-check=summary ./out`
→ `definitely lost: 639,936 bytes in 19,998 blocks`. Passing a VAR arg
(`mk(v)`) instead of a literal → 0 lost (no materialization).

## Why the obvious fix is wrong

Removing the `IR_DEFAULT_MEM` (relying on the body-head SymIsHiddenArgTemp
nil-init + STORE's release-old) fixes the leak in isolation BUT breaks
the self-hosted compiler: it compiles uforth.py with a cwd-DEPENDENT
`dataclass ctor not registered` error (argv[0] length changes the heap
layout, exposing an uninitialized-slot read somewhere the body-head
nil-init doesn't reach). So some hidden-arg-temp slot is NOT nil before
its first STORE, and the DEFAULT_MEM's tolerate-garbage zeroing is
load-bearing. Reverted 2026-07-23 after `make bench-uforth` caught it.

## ROOT CAUSE (2026-07-23 investigation) — it is NOT a nil-init gap

The original "un-nil'd slot" theory above is **wrong**. Verified by
instrumentation (counters on the two sites): every argIsManagedTemp temp
IS nil-init'd. The body-head pass that covers them is
**`ir_codegen.inc:6013`, inside `IREmitMachineCode`** (runs AFTER
`IRLowerAST`, so it DOES see temps lowering minted — unlike the parser's
pre-lowering `EmitManagedLocalsZeroInit`). Counters compiling uforth:
`create=273` (argIsManagedTemp skLocal temps) vs `zero=284` (all skLocal
tyAnsiString temps 6013 zeroed) → zero ≥ create, all covered. Main-body
temps are skGlobal (BSS-zeroed). No slot reaches STORE un-nil'd.

The real bug: removing the `IR_DEFAULT_MEM` **enables `IR_STORE_SYM`'s
release-of-old** (dormant in mainline: the pre-zero makes every store see
a nil slot, so release-old always no-ops and the prev handle merely
LEAKS). Enabling it exposes a latent **over-release of a SHARED managed
handle**:

- `EmitManagedLocalCleanup` (symtab.inc:5581) already releases these
  temps' LAST value at scope exit, and mainline does NOT corrupt — so the
  materialised values are generally owned rc-1 and releasable.
- Corruption only when the SAME shared handle recurs across iterations:
  mainline releases it ONCE (scope exit, rc K→K-1, survives); the fix
  releases it once PER ITERATION → rc underflows → the block is freed
  while still referenced. It happens to be a live proc-name buffer
  (`Procs[i].Name`), so a later `FindProc` misses → `dataclass ctor not
  registered: [CompileAction.create]` (2nd dataclass; `Word` already
  emitted). Confirmed: name buffer rc=2 at registration, then freed.

Why it hides: **native-allocator + full-uforth layout only**. Under
`-dPXX_LIBC_HEAP` (fresh addresses) and in small repros (1–2 dataclasses,
`mk('x')` in a loop) the freed garbage doesn't alias a live block, so
they compile clean — do NOT trust them. `-O0/-O1/-O2` all fail equally
(pure lowering, not an optimizer interaction).

Where the shared handle comes from: NOT concat — `PXXStrConcat`
(builtinheap.pas:717) always `PXXAlloc`s a fresh rc-1 block (or nil), so
BINOP results are safe. The suspect is a **user-CALL result classified as
owned-move at `ir_codegen.inc:2686`** (`IR_CALL, IRA>=0` → no retain) that
actually returns a shared handle without a net +1 — the NRVO / frozen-
result / aggregate-dest family (cf. [[project_variant_fn_return_forward_nrvo_corruption]]).

Both original candidates below enable release-old, so BOTH hit this.

## Correct fix (not yet done)

- **(a) Force the materialised value UNIQUE before storing it into the
  temp** (`AnsiStrUnique` / private clone at the argIsManagedTemp site),
  so release-old only ever frees a PRIVATE rc-1 buffer regardless of
  whether the source was shared. Clones only when rc>1 (the actual
  problem case); genuinely-owned rc-1 values pass through. Semantically
  safe — the param is `const` (callee borrows). Watch: don't let the
  wrap flip STORE_SYM off the move path into a double-retain (re-leak).
- **(b) Find & fix the specific user function returning a shared string
  without +1** (the STORE_SYM move-classification liar). Root fix, but
  needs a runtime trace to pin — the gdb hardware-watchpoint on the
  name-buffer refcount word is the tool (see below).

## Session-2 forensics (2026-07-23, gdb watchpoint — CONFIRMED cascade)

Reproduced with the fix applied, watching the failing name buffer. Method
that works (record it — the LIBC-heap profile does NOT reproduce this, the
NATIVE allocator layout is load-bearing):
1. Print the buffer address at RegisterProc when `name='CompileAction.create'`:
   `DbgWatchRel := Int64(Pointer(Procs[ProcCount].Name))`.
2. Run with ASLR OFF (`setarch -R`, and gdb `set disable-randomization on`)
   → the heap VA is DETERMINISTIC and identical across runs of the same
   binary. Capture the printed address in gdb's own env (one throwaway run).
3. `gdb -batch -ex "set disable-randomization on" -ex starti
   -ex "watch *(int*)(ADDR+8) if *(int*)(ADDR+8)==28" -ex continue -ex bt`.
   Frame pointers are ABSENT → gdb's `bt` dies at frame 1; scan the stack
   (`x/80a $rsp`) and pipe through `tools/vgsym.py <p26>.map` (build the
   compiler with `--proc-map`) to symbolise the return addresses.

Findings:
- The buffer is FREED WHILE LIVE: at the failure `Procs[824].Name` still
  points at it, `rc=1`, but bytes 8-11 hold the int `28` (a `RecName =
  REC_UCLASS_BASE+ci`). Watchpoint on `+8`: the 28 is written by
  **`PyAnnTypeAt+0x1afe`** — a `Syms[garbage].RecName := …` WILD WRITE
  through a corrupted `SymIdx`, i.e. `PyAnnTypeAt` is a downstream VICTIM
  writing into a Syms entry that overlaps the buffer, not the perpetrator.
- Watchpoint on the block header (`ADDR-16`) for a freelist-pointer write
  (`> 1e8`): the block is handed to the free list by **`PXXFree`**, called
  from a runtime release blob (return addr in the low `0x4000xx` blob
  region — NOT the AnsiStr-release path a `ud2` there watches, which is why
  the data-ptr `ud2` never fired). So it is a **cascade**: an EARLIER
  over-release corrupted the free list, CompileAction.create's buffer was
  then allocated at a doubly-owned address, and the other owner frees it.
- The registration path for the freed name is itself clean: `PyRawName`
  (pyparser.inc:1853) and `GetTokenStr` (parser.inc:702) both build FRESH
  owned strings via AppendChar. So the aliasing is INDIRECT (freelist
  damage), not a direct borrow of that name — the ROOT over-free is an
  earlier hidden-arg-temp release elsewhere and is NOT yet pinned.

Refined fix note: `AnsiStrUnique` (candidate a) will NOT work — it is
rc-gated, and the liar UNDER-counts (the temp's borrowed ref is not in the
rc), so unique sees rc≤1 and skips the clone. The correct fixes are
either **(b)** find the mis-classified callee and make its Result carry a
real +1, or a **deep byte-copy** (not COW) of the materialised value into
the temp so the temp owns a genuinely private buffer AND release the
source when the classification says it was owned. Next step to pin the
root over-free: watch free-list integrity from process start, or trap in
`PXXFree` when freeing a block whose rc word is still ≥1 (a free of a
still-referenced managed block = the smoking gun), and backtrace via the
stack-scan method above.

Gate any fix on: `make test` + self-host fixedpoint + compile uforth.py
FROM THE REPO ROOT (`./compiler/pascal26 ~/projects/uforth/uforth.py
/tmp/x`, not just test-uforth's workdir) + `make bench-uforth` + the
valgrind probe above going to 0.
