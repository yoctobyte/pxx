---
summary: "The dlopen loader is unverified by an actual RUN on arm32/aarch64 because this host has no cross ld-linux or cross libc — /usr/arm-linux-gnueabihf/lib and /usr/aarch64-linux-gnu/lib do not exist at all. Host provisioning, not code: no ticket resolving will make a cross libc appear. Split out of feature-real-dynlib-loader so that feature stops resurfacing at p45 with nothing actionable in it."
track: B
prio: 20
type: chore
status: backlog
owner: unassigned
blocked-by: []
gated-by: host-provisioning (owner-only; not a code change)
---

# No cross loader on this host blocks the dynlib arm32/aarch64 run

> **NOT DISPATCHABLE — no agent in any lane can close this.** It needs packages on
> the owner's box, and package installs on the owner's boxes are the owner's.
> Premise re-verified 2026-08-30 by frankB against the host rather than assumed:
> `/usr/arm-linux-gnueabihf/lib` and `/usr/aarch64-linux-gnu/lib` still do not
> exist and there is no cross `ld-linux` anywhere; `qemu-arm` and `qemu-aarch64`
> **are** present, so the missing half is precisely the libc, exactly as filed.
>
> The marker is here because `prio:` cannot carry this. A bulk re-triage rewrites
> prices and leaves non-price fields alone (`ab584382e` swept two owner rulings
> that way on 2026-08-25 — face 179 in
> [[feature-a-a-refusal-is-a-claim-with-a-date-on-it]]), so a low number is not a
> hold. `NOT DISPATCHABLE` is read by `tools/progress.py`'s `_NODISPATCH_RE` and
> `ready` prints the warning; a number would just rank it quietly.
>
> **This ticket is the GOOD version of the failure** — it is the third item in one
> night that ranked as work while being answerable by nobody in a lane, and the
> only one of the three that said so in its own summary. Left as-is it still costs
> every agent that reaches it one read to discover that.

Item (b) of [[feature-real-dynlib-loader]], split out on 2026-08-29 when the
other open item was completed. **This is a host-provisioning gap, not code.**

## Measured, again, today

```
absent:  /usr/arm-linux-gnueabihf/lib/ld-linux-armhf.so.3
absent:  /usr/aarch64-linux-gnu/lib/ld-linux-aarch64.so.1
```

Neither sysroot directory exists at all — this is not a missing symlink, there
is no cross libc on the box. The loader **cross-compiles** for both targets; what
cannot be done here is *running* the result and watching a real `dlopen` resolve
a real symbol, which is the only assertion worth making about a loader.

## Why it is filed separately rather than kept as an open item

It kept `feature-real-dynlib-loader` alive at p45 for months with nothing a
worker could act on: the ranker offered it, someone read it, found item (b)
blocked on the absence of a file, and re-parked it. That is the exact pattern
CLAUDE.md warns about — *"parking it at prio 10 keeps it in the ranker's scan
forever at zero value"* — except at 45 it was near the top of Track B.

Kept as a chore at 20 rather than closed, because it is genuinely wanted and
becomes a five-minute job the moment the box has a sysroot.

## What would close it

Either a cross sysroot on this host (`gcc-arm-linux-gnueabihf` /
`gcc-aarch64-linux-gnu` supply `ld-linux` and libc), or a run on a native
aarch64/arm32 box. Track T's fleet is the natural home for the second — if a
watcher host is ever aarch64, this becomes one job rather than a provisioning
request.
