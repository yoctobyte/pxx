---
prio: 45
---

# System stack-frame intrinsics: get_frame / get_pc_addr / get_caller_stackinfo

- **Type:** feature (Track A — System intrinsics)
- **Status:** done
- **Blocks:** [[feature-pascal-corpus-fpcunit]] — the LAST wall in fpcunit.pp itself.

## What needs them
fpcunit.pp calls them with no `uses` (FPC has them in System):

```pascal
function CallerAddr: Pointer;
begin
  bp := get_frame;
  pcaddr := get_pc_addr;
  get_caller_stackinfo(bp, pcaddr);
  if bp <> nil then get_caller_stackinfo(bp, pcaddr);
  Result := pcaddr;
end;
```

## They are DIAGNOSTIC-ONLY — that changes the calculus, but does not settle it
`CallerAddr`'s result is only ever fed to `AddrsToStr`, which prints `'n/a'` when the
address is 0. It records WHERE an assertion failed, in the report. Pass/fail is entirely
unaffected.

So unlike [[feature-tobject-getinterface-guid-table]] — where returning False would have
been a silent LIE — a nil here lands on the unit's own sanctioned "no address" path, and
it is VISIBLE (`n/a`), not silent.

That makes a stub defensible. It does not make it free: a permanently-nil `get_frame` is
a System intrinsic that quietly does nothing forever, and the next caller may not be
diagnostic-only. So it is a decision, not a drive-by.

## The two honest options
1. **Real frame walk (preferred).** pxx emits full frame pointers (`push rbp; mov rbp,
   rsp`), so the chain IS walkable: `get_frame` = current frame pointer, and
   `get_caller_stackinfo(bp, addr)` = `addr := [bp+8]; bp := [bp]` on x86-64, with the
   per-target equivalent elsewhere. Needs a small codegen intrinsic (the frame pointer is
   not reachable from Pascal), so it is Track A, and it is per-backend.
2. **Explicitly-stubbed intrinsics.** Return nil / no-op, so `CallerAddr` yields nil and
   fpcunit reports `n/a`. Cheap and correct-by-the-unit's-own-contract, but must SAY so —
   in the intrinsic's own comment and in the release notes — or it becomes folklore.

Recommend (1); it is not much more work than (2) on x86-64 + aarch64 (Track O's stated
per-backend scope), and (2) can be the fallback on the targets where the frame layout is
not worth chasing.

## Gate
`make test` + self-host byte-identical + cross.

## Log
- 2026-07-13 — opened. It is the only thing left between us and fpcunit.pp compiling;
  everything else in the chain now works (testutils substituted, LineEnding, TFPList,
  GetInterface, MethodAddress, packed arrays).
- 2026-07-13 — resolved, commit d963d5d0.
