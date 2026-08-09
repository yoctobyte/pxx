---
track: A
prio: 75
type: feature
summary: "Set ONE PXX_THREADSAFE conditional define whenever ThreadSafeMode is on, every target — so RTL units can gate a declaration on 'threads are enabled' instead of on a lock-implementation flag. Unblocks TThread in Classes; decided by the user 2026-08-09"
---

# `{$IFDEF PXX_THREADSAFE}` — one define meaning "threads are enabled"

- **Type:** feature — Track A (`compiler/lexer.inc`)
- **Opened:** 2026-08-09
- **Decided by:** the user, 2026-08-09, resolving
  [[decide-threadsafe-gate-is-reach-based-not-use-based]]. Filed by Track B,
  which needs it but does not own the file.
- **Urgency:** small and self-contained, and a Track B change waits on it
  landing in the next pin. Not urgent because anything is broken.

## The change

Set a define — `PXX_THREADSAFE` — whenever `ThreadSafeMode` is on, for **every**
target. `compiler/lexer.inc` already has the shape a few lines away:

```pascal
if ThreadSafeMode and ((TargetArch = TARGET_I386) or ... ) then
begin name := 'PXX_TS_SOFTLOCK'; PasDefine(name); end;
if ThreadSafeMode and (TargetArch = TARGET_X86_64) then
begin name := 'PXX_TS_HARDLOCK'; PasDefine(name); end;
```

so this is one more unconditional-on-`ThreadSafeMode` `PasDefine`.

## Why the two existing defines are NOT it

`PXX_TS_HARDLOCK` and `PXX_TS_SOFTLOCK` answer **which lock implementation is in
use** — the x86-64 codegen-emitted BSS spinlock, versus the Pascal-level
spinlock the 32-bit and aarch64 targets take in `PXXAlloc`/`PXXFree`. They exist
so runtime code can tell those two apart. They are not a flag for "threading is
enabled": neither covers all targets on its own, and a unit that gated a
DECLARATION on one of them would be keying off a correlated implementation
detail rather than the thing it means.

Doing that would be a workaround in ifdef form — the same class the platonic-code
rule rejects, and just as misleading to the next reader. Hence a define that says
what it means.

## What it unblocks

Item 1 of [[compat-pascal-thread-api-surface-differs-from-fpc]]: `TThread` where
FPC code looks for it. `lib/rtl/classes.pas` becomes

```pascal
uses sysutils, platform{$ifdef PXX_THREADSAFE}, palthreadobj{$endif};

{$ifdef PXX_THREADSAFE}
type
  TThread = palthreadobj.TThread;
{$endif}
```

so a threaded build gets `TThread` from `uses Classes` exactly as on FPC, and a
non-threaded build never parses `palthread` and so never trips the `__pxxclone`
gate. That replaces the reachability-analysis option the decide ticket was
weighing, at a fraction of the cost.

**The re-export half is already verified** (2026-08-09, pinned): pxx's `uses` is
not transitive, so `classes` has to alias the type — and a program that uses only
the aliasing unit CAN subclass through the alias and override a virtual method.
Measured on a three-unit repro; prints `subclass ran, tag=7`. So once this define
exists the Track B change really is those few lines.

## Why this is the right shape beyond TThread

The same pattern serves any RTL unit that wants to offer more surface when
threading is on without taxing programs that never spawn — and the reasons
`--threadsafe` stays opt-in are not only code size and speed (user, 2026-08-09):
microcontroller targets where neither matters, and single-threaded applications
where the whole question is moot. That was settled long ago; this define lets
units respect it declaratively.

## Gate

Track A's usual: `make test` + self-host fixedpoint (byte-identical). The define
is additive and inert until something gates on it, so the risk is a name
collision, nothing more. Worth one probe asserting `{$ifdef PXX_THREADSAFE}` is
false by default and true under `--threadsafe`, on x86-64 and one 32-bit target.
