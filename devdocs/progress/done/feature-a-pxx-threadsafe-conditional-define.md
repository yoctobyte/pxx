---
track: A
prio: 75
type: feature
summary: "Set ONE PXX_THREADSAFE conditional define whenever ThreadSafeMode is on, every target — so RTL units can gate a declaration on 'threads are enabled' instead of on a lock-implementation flag. Unblocks TThread in Classes; decided by the user 2026-08-09"
status: done
owner: agent-AN
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

## The name: `PXX_THREADSAFE`, not `THREADSAFE`

Prefixed deliberately (user, 2026-08-09): a bare `THREADSAFE` is exactly the
identifier an application programmer would `{$DEFINE}` in their own code, and a
collision there would silently change what the RTL declares.

It also matches the existing convention, which turns out to be a clean split.
The UNPREFIXED defines are precisely the FPC-compatibility ones — `CPU64`,
`CPUX86_64`, `CPUARM`, `LINUX`, `FPC`, `ENDIAN_LITTLE` — names FPC itself
defines, so portable source can test them. Everything pxx invents carries the
prefix: `PXX`, `PXX_MANAGED_STRING`, `PXX_VERSION`, `PXX_PLATFORM_*`,
`PXX_HAS_*`, `PXX_ESP_*`, `PXX_TS_*`. This define is pxx's own invention, so it
takes the prefix.

## Do NOT reuse `PXX_HAS_THREADS` either

It already exists, it is tempting, and it is a different axis. `PXX_HAS_THREADS`
is a PLATFORM CAPABILITY — set for posix, absent for ESP-bare — answering "can
this target do threads at all". It says nothing about whether THIS BUILD enabled
the thread-safe runtime. A posix build with no `--threadsafe` has
`PXX_HAS_THREADS` defined and must still not parse `palthread`.

So the three near-misses, all of which would compile and all of which would be
wrong:

| define | actually means | why it is not this |
| --- | --- | --- |
| `PXX_TS_HARDLOCK` | x86-64's codegen BSS spinlock is in use | per-target; absent on 32-bit `--threadsafe` builds |
| `PXX_TS_SOFTLOCK` | the Pascal-level spinlock is in use | per-target; absent on x86-64 |
| `PXX_HAS_THREADS` | the platform is capable of threads | true without `--threadsafe` |

## Why the two existing lock defines are NOT it

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

## Note 2026-08-09: a design that may make this ifdef unnecessary later

Do this one anyway — it is one `PasDefine` and it unblocks `TThread` in
`Classes` now. But the follow-up question ("could the compiler auto-detect
threading?") led to measuring what Delphi and FPC actually do, and the answer is
that they do not detect anything: `IsMultiThread` is a RUNTIME boolean, set when
a thread is created, and the lock primitives branch on it. Measured, the branch
costs +5% over an unlocked refcount where an unconditional lock costs +276%.

If pxx adopts that ([[decide-ismultithread-runtime-flag-vs-compile-time-mode]]),
`TThread` goes into `Classes` unconditionally and this ifdef comes back out.
That is not a reason to wait — the define is cheap, useful on its own, and
removing it later is trivial.

## DONE 2026-08-09 — and it was NOT one more `PasDefine` next to the others

The ticket's own sketch was to add the define beside `PXX_TS_SOFTLOCK` /
`PXX_TS_HARDLOCK`, "one more unconditional-on-`ThreadSafeMode` `PasDefine`". I
did exactly that, then ran the probe the Gate section asks for — and it read
**FALSE on x86-64 `--threadsafe`**, which is the target Track B builds on.

`PasApplyTargetDefines` begins:

```pascal
if TargetArch = TARGET_X86_64 then Exit;
```

That `Exit` is right for what it was written for (on the host there are no CPU
defines to swap), but every block appended *below* it over time is dead on the
DEFAULT target. So the define went in **above** the `Exit`, and the probe then
reads correctly on all four cells.

### The probe was load-bearing, not ceremony

The one-liner compiled, self-hosted byte-identical, and would have shipped inert
on the primary target. The Gate line asking for `{$ifdef PXX_THREADSAFE}` to be
asserted true AND false is the only thing that caught it — worth noting because
this is a define, and a define that is silently never set looks exactly like a
feature that works.

### A pre-existing bug found by the same probe

`PXX_TS_HARDLOCK` is set at one place, below that `Exit`, guarded on
`TargetArch = TARGET_X86_64` — the one target that cannot reach it. **The
condition is unsatisfiable, so the define is dead on every build**, on HEAD and
on `pinned` alike. Its only consumer is `builtinheap.pas`:

```pascal
{$ifndef PXX_TS_HARDLOCK}
  PXXRecordRelease(inst, desc);
{$endif}
```

so an x86-64 `--threadsafe` build takes the class-finalization path that the
define exists to suppress — the one the lexer's own comment says would be
"racing the allocator". Filed as
[[bug-a-x86-64-early-exit-skips-target-defines]] rather than fixed here: it
switches a runtime path on for the first time and deserves its own gate, and
this ticket is meant to be small and land in a pin.

### Verified, all four cells

| build | `PXX_THREADSAFE` |
| --- | --- |
| x86-64, default | off |
| x86-64, `--threadsafe` | **on** |
| i386, default | off |
| i386, `--threadsafe` | **on** (with `PXX_TS_SOFTLOCK`, as expected) |

aarch64 and arm32 `--threadsafe` cross-build clean.

### Gate

`test/threadsafe_define.pas`, run BOTH ways from `test-threads` — with only the
on case, a define set unconditionally would pass. Full gate + `make stabilize`
+ `make pin`, since Track B is waiting on it reaching `$(PXX_STABLE)`.

## Log
- 2026-08-09 — resolved, commit 538e59141.
