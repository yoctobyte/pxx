# Frozen-string function Result is a shared global → not reentrant / thread-unsafe

- **Type:** bug (latent, correctness) — Track A (parser / codegen)
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** review while adding decl-order gating (user spotted it).

## Symptom / hazard

A function returning a **frozen string** (`tyString`, the compiler's fixed-capacity
internal string model) gets its `Result` slot allocated as a **program GLOBAL**,
not a stack local:

```pascal
{ parser.inc, ParseSubroutine, return-value slot }
else if retType = tyString then
begin
  savedCurProc := CurProc;
  CurProc := -1;                 { force global scope }
  AllocVar('Result', retType);
  CurProc := savedCurProc;
  Procs[procIdx].RetSymIdx := SymCount - 1;
  Syms[SymCount-1].Kind := skGlobal;   { one shared BSS slot for ALL calls }
end
```

So every invocation of that function writes the **same** BSS slot. Consequences:
- **Not reentrant:** if such a function recurses (directly or mutually), the inner
  call overwrites the outer call's `Result` before the outer has copied it out.
- **Not thread-safe:** two threads calling the function race on the slot
  (`--threadsafe` builds included).

Only frozen-string returns are affected. Managed-string (`AnsiString`, the user
default) returns use the normal ARC/handle path; record and dyn-array returns use
local/hidden-dest slots. The compiler self-builds with frozen strings, so this is
exercised by the compiler itself — it works today only because no frozen-string
function recurses in a way that observes the clobber before the caller copies the
value out (fragile by accident, not design).

## Likely intent

A frozen string is ~`STRING_CAP + 8` bytes; the value is returned by copying from
`Result`'s address after the frame is gone, so a *stable* address was wanted. A
global gives that, but at the cost of sharing. The correct model is a per-call
home: a hidden caller-allocated return slot (like the aggregate/record-return
`ProcAggregateDestSym` path), or a stack local copied out before the epilogue tears
the frame down.

## Fix sketch

Route frozen-string returns through the existing hidden-return-slot mechanism (the
caller passes the destination address; `Result` aliases it), the same way
struct-by-value returns already work — instead of a shared global. Must keep
self-host byte-identical and the `--threadsafe` self-build green.

## Acceptance

- A recursive frozen-string function returns correct values (a focused test: e.g.
  a recursive build-a-string that would clobber a shared slot).
- No shared global `Result`; `--threadsafe` self-build stays byte-identical.
- Self-host byte-identical; cross green.

## Notes

- Orthogonal to the decl-order gating (v93) that surfaced it. Pre-existing.
- The decl-order gating explicitly does NOT gate this synthetic global (it is
  allocated with PreScanPass=False, so `StampDeclSeq` skips it) — otherwise the
  function body could not see its own Result.

## Fix proposal — refined (2026-06-30)

Route frozen-string returns through the **existing hidden-destination aggregate
return path** (the one records/sets already use), instead of the shared global.

Concretely:
1. Allocate `Result` for a `tyString`/`tyFixedString`/`tyShortString` function as a
   routine **local** (the normal `CurProc >= 0` AllocVar), not `CurProc := -1` +
   `Kind := skGlobal` (parser.inc ParseSubroutine, the `else if retType = tyString`
   block ~12523).
2. Give the function a hidden destination param like aggregate returns
   (`ProcAggregateDestSym`): the caller allocates the return buffer and passes its
   address (r10 on x86-64 / the per-target dest register already used for records).
3. The epilogue copies the local `Result` into the caller's dest and returns that
   pointer — the existing `TypeIsAggregate(...) and ProcAggregateDestSym >= 0`
   branch in `EmitProcEpilog` (symtab.inc) already does exactly this with rep movsb;
   the `tyString` branch right below it (which returns the global address) is what
   gets removed.
4. Call sites: allocate the hidden dest temp and pass it, as record-by-value calls
   already do.

**Do NOT widen `TypeIsAggregate` to include tyString globally** — tyString is
special-cased in many codegen paths (load/store width, concat, length); flipping it
to "aggregate" everywhere is high-risk. Instead gate the *return* path on
`TypeIsFrozenString(retType)` so only the return ABI changes, reusing the aggregate
copy/dest machinery.

**Per-backend:** the frozen-string return branch exists in every backend's epilogue
+ call lowering (x86-64 ir_codegen.inc, i386 ir_codegen386.inc, arm32, aarch64,
riscv32, xtensa). Each needs the dest-pointer return instead of the global address.
Self-host is byte-identical-sensitive (the compiler returns frozen strings
pervasively) → expect to reseed and run the full cross matrix. Sizeable, careful
multi-target change — not a quick edit.
