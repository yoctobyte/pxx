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

## Attempt 1 (2026-06-30, Track A) — copy-out model PROVEN INSUFFICIENT, reverted

Implemented the refined proposal exactly (copy-out-to-fixed-local), full multi-target.
Reverted clean; tree green. Findings (these de-risk the next attempt):

**The wiring is almost entirely mechanical and the machinery already exists:**
- Added `RetViaHiddenDest(tk) = TypeIsAggregate(tk) or TypeIsFrozenString(tk)` and
  `AggRetCopySize(retSymIdx)` in symtab.inc, then swapped `TypeIsAggregate(...)` →
  `RetViaHiddenDest(...)` at exactly the *return-ABI* sites (NOT the arg site
  `ir.inc:3787`, NOT the C frontend `cparser.inc` — Track C, C has no frozen
  returns): parser.inc 12539/12555, ir.inc 191/947, all 6 epilogue gates in
  symtab.inc, and the call-site dest loads in every `ir_codegen*.inc`
  (`TypeIsAggregate(Procs[procIdx].RetType)` is *always* the return convention in
  the codegen files — a blanket per-file token swap is correct there).
- `EmitAggregateDestStash` (prologue) is already fully generic — gated only on
  `ProcAggregateDestSym>=0`, so it auto-handles frozen returns once the parser
  allocates the dest sym. No per-backend prologue edit needed.
- Result: small recursive frozen-string test fixed (`Build(5)=5`, was `0`),
  managed-mode self-host **byte-identical** (the default `make` build is MANAGED —
  `PXXFLAGS` empty keeps `PXX_MANAGED_STRING` defined — so the change is *dormant*
  there and proves nothing about frozen mode).

**Why it fails (the real blocker — a capacity-semantics problem, not a wiring bug):**
- The frozen self-build (`-uPXX_MANAGED_STRING`) reaches a compiler that
  **segfaults compiling anything**. Root cause: the copy-out model makes `Result`
  a routine **local**, which is capped at `LOCAL_STR_CAP+8 = 264` bytes. The old
  shared global was `STRING_CAP+8 = 8 MB`. Confirmed directly: a frozen function
  building a 1000-char result now returns **len=256** (truncated), and the compiler
  builds frozen-string *results* well over 256 chars (mangled names, generated
  lines, error text) → writing them into the 264-byte Result local overflows the
  frame → segfault.
- So copy-out-to-fixed-local silently **shrinks frozen-string-result capacity 8 MB
  → 256 chars**. That is both a crash (compiler) and a semantic regression (user
  programs). Sizing the local bigger trades the crash for stack-overflow risk under
  recursion (capacity × depth on the frame).

**What the next attempt must do instead — true NRVO (Result *aliases* the caller dest):**
- Don't give the callee a separate fixed-size Result local. Make `Result` an
  **indirect** slot: its frame slot holds the caller's dest pointer (already stashed
  by `EmitAggregateDestStash`), and every frozen `Result` load/store/address in the
  body redirects through that pointer (Result behaves like a `var`-param). Capacity
  then equals the *caller's* storage, so 8 MB is preserved.
- The caller must supply a dest of adequate capacity. For a real target
  (`g := F()`) pass the target's address. For an **expression temp**
  (`writeln(F())`, `F()+x`) the caller still needs a big buffer — i.e. the temp
  `IRAppendCall` allocates must be `STRING_CAP`-capable, but **per-call-site**
  (distinct global per site) so recursion/expression nesting can't clobber it (the
  reentrancy fix). A per-site 8 MB BSS temp is the same memory shape as today's
  global Result, just no longer shared across active calls.
- This is the "high-risk, many-sites" redirect the proposal warned against, but
  scoped to *Result accesses only*. It is the part that needs a deliberate design +
  the user's sign-off on capacity (keep 8 MB? or formally cap frozen results at
  shortstring-like 255 and update docs — arguably more FPC-like, but a behavior
  change). **Parked for that decision** rather than guessed at unattended.

**Status:** stays in backlog. Wiring approach is validated and mechanical; the open
question is the Result *home* (NRVO redirect + per-site big temp vs. an agreed
capacity cap). Pick that first, then the rest is the mechanical swap above.
