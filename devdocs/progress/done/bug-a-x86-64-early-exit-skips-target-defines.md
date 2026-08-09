---
track: A
prio: 55
type: bug
summary: "PasApplyTargetDefines returns early on x86-64, so every define appended after that Exit is dead on the DEFAULT target — PXX_TS_HARDLOCK is therefore never set on any build, and builtinheap takes the racing path it was written to avoid"
status: done
owner: claude-A
---

# An early `Exit` makes later target defines dead on x86-64

`compiler/lexer.inc`, `PasApplyTargetDefines`:

```pascal
begin
  { PasInitDefines seeds host (x86-64) defines before option parsing; once the
    target is known, swap them so ifdef CPU... branches see the target. }
  if TargetArch = TARGET_X86_64 then Exit;      { <-- }
  ...CPU define swap...
  ...PXX_ESP_BARE...
  ...PXX_TS_SOFTLOCK...
  ...PXX_TS_HARDLOCK...
end;
```

The `Exit` is correct **for what it was written for**: on the host target there
are no CPU defines to swap. But blocks were later appended *below* it, and those
are unconditionally dead on the default target — the one nearly everything is
built for.

## Measured consequence: `PXX_TS_HARDLOCK` is never defined, anywhere

It is set at exactly one place, below the `Exit`, guarded on
`TargetArch = TARGET_X86_64` — the one target that can never reach it. So the
condition is unsatisfiable and the define is dead on **every** build.
Confirmed on HEAD and on `pinned` (so pre-existing, not from recent work):

```
pxx --threadsafe probe.pas   ->  {$ifdef PXX_TS_HARDLOCK} is FALSE
```

Its only consumer is `compiler/builtin/builtinheap.pas`:

```pascal
{$ifndef PXX_TS_HARDLOCK}
  PXXRecordRelease(inst, desc);
{$endif}
```

so `PXXRecordRelease` runs on x86-64 `--threadsafe` builds, which is precisely
what the define was introduced to prevent. From the lexer's own comment:

> --threadsafe on x86-64: the heap lock is the codegen-emitted BSS spinlock,
> which Pascal-level runtime code cannot take. Paths that would need it from
> Pascal (PXXClassFinalize's string/dynarray pass) gate on this define and keep
> the pre-existing benign leak instead of **racing the allocator**.

So a threaded x86-64 program takes the allocator-racing path in class
finalization. Latent — it needs a real thread race to show — and racing the
allocator is the failure mode nobody debugs successfully.

## Fix

Narrow the early return to the CPU-define swap it was meant for:

```pascal
if TargetArch <> TARGET_X86_64 then
begin
  ...CPU define swap...
end;
...everything else, unconditionally...
```

`PXX_ESP_BARE` and `PXX_TS_SOFTLOCK` are unaffected in practice (their own
conditions already exclude x86-64), so the only behaviour change is
`PXX_TS_HARDLOCK` becoming defined on x86-64 `--threadsafe` for the first time —
which is what it always meant, and is exactly why this wants its own gate rather
than riding along with something else.

## Gate

`make test` + self-host fixedpoint, and specifically the `--threadsafe`
self-host (`test-core`), which is the only job that exercises the changed path
(`project_globfix_cap_threadsafe_selfhost_landmine` notes it is also the only
one that shows threadsafe-only breakage). Assert the define is TRUE under
`--threadsafe` on x86-64 and FALSE without, alongside the `PXX_THREADSAFE` probe
that found this.

## Found by

Landing [[feature-a-pxx-threadsafe-conditional-define]]. Its one-line
`PasDefine` was appended in the obvious place — next to the two lock defines —
and the probe showed it FALSE on x86-64 `--threadsafe`. That define now sits
ABOVE the `Exit`; this ticket is the underlying cause, left separate because it
switches on a runtime path and deserves its own gate.

## 2026-08-09 — FIXED

The early return is now a scoped `if TargetArch <> TARGET_X86_64 then begin …
end` around the CPU-define swap it was written for, so nothing appended below it
is dead any more — the shape matters as much as the fix, because the failure
mode was "the next block someone appends here is silently dead".

Measured, x86-64:

| build | HARDLOCK | SOFTLOCK | THREADSAFE |
| --- | --- | --- | --- |
| plain | no | no | no |
| `--threadsafe` | **yes** (was `no`) | no | yes |
| `--threadsafe`, PINNED (control) | no | no | yes |

and aarch64 `--threadsafe` still answers SOFTLOCK yes / HARDLOCK no with the
CPU defines swapped, so the block that moved is intact.

The pinned row is the point: the define had never been true on any build, so
this is the first time `builtinheap`'s `{$ifndef PXX_TS_HARDLOCK}` guard
actually suppresses `PXXRecordRelease` on an x86-64 threaded build.

### Verified

- `test/threadsafe_lockdefine.pas`, run both ways from `test-threads` beside the
  existing `threadsafe_define.pas` — both spellings asserted, since an
  unconditionally-set define would pass the ON case alone.
- `threadsafe_define.pas`'s header comment updated: it no longer has to sit
  above an early return, and saying it does would send the next reader looking
  for a constraint that is gone.
- `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN, plus
  `make test-core` — the `--threadsafe` self-host named in the Gate section
  above, and the only job that exercises the path this change switches.


## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.
