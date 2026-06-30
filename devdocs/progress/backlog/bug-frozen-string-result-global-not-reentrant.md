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
