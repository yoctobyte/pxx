---
summary: "main-body interface as-cast temp is released at the wrong time vs FPC (destructor timing) — differing exit checksum, no crash"
type: bug
prio: 30
---

# Main-body interface `as`-cast temp finalized at the wrong time (vs FPC)

- **Type:** bug (Track A/P — COM interface temp lifetime in the main program body).
  Wrong-value divergence vs the FPC oracle; **no crash**.
- **Found:** 2026-07-18, spun out of [[bug-pascal-interface-finalization-crash]]
  (the crash half is fixed; this benign timing half remained).

## Symptom

pasmith `--intfs 3` seed **53002** (regenerated program): every per-statement trace
checkpoint matches FPC, but the final exit checksum differs
(pxx `15884096175605541609` vs FPC `2032288769329671358`). Delta-debugging the Mix
trace shows the ONLY difference is destructor timing: FPC keeps the `(iw0 as IPas1)`
temp created in the **main program body** alive until end-of-main, so `TIfc.Destroy`
for iw0 runs AFTER `writeln(cs)` (its `Mix(8000)/Mix(fi)` do NOT fold into the printed
checksum). pxx releases the object earlier, so those Mix calls land inside `cs`.

## Why (mechanism, verified)

Inside a routine, an `as`-cast COM-interface temp is skLocal, now correctly AddRef'd
(commit 8e2d112e) and released at scope exit by EmitManagedLocalCleanup — matches FPC.

In the **main program body** `CurProc < 0`, so the temp is **skGlobal** (BSS —
zero-initialised, which is why it never crashes like the skLocal case did). There is:
- no AddRef on it (the retain in IRMaterializeIntfCast is skLocal-only), and
- no program-exit finalization pass over skGlobal COM-interface temps.

So the main-body temp holds no owning reference and the object dies when the global
`iwX` is nil'd, not at end-of-main.

Minimal repro (main-body case; procedure case already matches FPC):
```pascal
{$mode objfpc}
type
  IA = interface ['{a...01}'] function GetV: longint; end;
  IB = interface ['{b...02}'] function GetW: longint; end;
  TC = class(TInterfacedObject, IA, IB) fi: longint;
    constructor Create(v: longint); destructor Destroy; override;
    function GetV: longint; function GetW: longint; end;
  ...
var a: IA;
begin
  a := TC.Create(7);
  writeln('cast=', (a as IB).GetW);
  a := nil;
  writeln('after nil');   { FPC: destroy AFTER this line; pxx: BEFORE }
end.
```

## Fix

Match FPC end-of-main temp lifetime: (1) AddRef the main-body as-cast temp (as the
skLocal path does), and (2) add a program-exit finalization pass that releases
skGlobal COM-interface **hidden** temps (name='') after the main body runs. Must be
careful: the temp aliases an instance that may already be freed via `iwX := nil` — so
(1) is a prerequisite for (2) (the retain keeps it alive until the exit release).

## Acceptance

- The main-body minimal above destroys the object AFTER `after nil`, matching FPC.
- pasmith `--intfs 3` seed 53002 exit checksum matches FPC.
- Gate: `make test` + self-host byte-identical (compiler declares no interfaces, so
  it stays byte-identical) + cross.

## Note

Low priority: benign (correct values, no crash, no leak — the object IS destroyed,
just earlier). The crash sibling was [[bug-pascal-interface-finalization-crash]].
Cross-check [[project_com_interface_default_and_lifetime]],
[[project_interface_single_pointer_abi_b337]].

## Log
- 2026-07-18 — resolved, commit 579142c7.
