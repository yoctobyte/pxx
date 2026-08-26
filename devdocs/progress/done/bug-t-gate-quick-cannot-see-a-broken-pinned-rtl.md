---
track: T
prio: 65
type: bug
blocked-by: []
summary: "A Track A change that adds a builtin and uses it from lib/rtl breaks every $(PXX_STABLE) build the moment it lands, because stable_linux_amd64/default/builtin/ is a FROZEN copy — and gate.sh quick is green through it, because the quick gate never builds anything with the pinned binary. It happened on 2026-08-21 and Track B/D/E were dead on master until the next pin. A ~1s canary closes it."
status: done
owner: pxx-aa
---

# `gate.sh quick` is structurally blind to a broken pinned RTL

- **Track T** (`tools/gate.sh` — T owns the tool). The *bug* it would have caught
  was Track A's and is already fixed (pin v369); this ticket is only about the
  hole.

## What happened

`97b1812fe` (Track A, [[feature-a-emitted-nil-checks]]) added `PXXNilRefHook` to
`compiler/builtin/builtinheap.pas` and installed it from `lib/rtl/sysutils.pas`.
Both files are live sources, the change was coherent, and the full per-fix loop
was green: `make compiler/pascal26` reached its fixedpoint and `tools/gate.sh
quick` passed.

It still broke master for three other lanes. `make pin` **freezes** the builtin
RTL sources into `stable_linux_amd64/default/builtin/`, so `pinned` was still
compiling the pre-hook `builtinheap.pas` against the post-hook `sysutils.pas`:

```
pascal26:4750: error: undefined variable (PXXNilRefHook)
  near: PXXIoErrorHook   SysRaiseIoError  PXXNilRefHook >>>   SysRaiseAccessViolation
```

Every `$(PXX_STABLE)` build — Track B, D, E, `make lib-test`, `make demos` —
failed from that commit until the v369 pin. It was found by accident, by a Track
A session compiling an unrelated scratch program with `pinned`.

## Why the gate cannot see it, and why that is not an accident

`gate.sh quick` runs the self-host fixedpoint and the quick testmgr tier. Both
build with the **freshly built** compiler, which has the new builtin in it. The
pinned binary — the thing three lanes actually build against — is never invoked.
So the gate is not weak here, it is looking somewhere else entirely: this break
lives exactly in the seam between the two, and nothing currently stands in that
seam.

Track T's own sweep would have caught it eventually (its wider tiers build lib),
but "eventually, one lane over" is how three tracks lose an evening.

## The fix is one cheap step, not a new tier

Add a canary to `gate.sh` (all modes — it is ~1 second):

```
./stable_linux_amd64/default/pinned <a program that `uses SysUtils`> /tmp/...
```

Compile only; running it is not the point. Any live-RTL-vs-frozen-builtin
mismatch is a compile error, which is the whole failure mode. `test/` already
has plenty of `uses SysUtils` programs to point it at, so it needs no new
fixture.

Consider asserting the reverse direction too — that the frozen builtin set is
byte-identical to `compiler/builtin/` *when the pin is current* — but that is a
`progress.sh check`-shaped assertion and would fire (correctly, but noisily) on
every Track A commit between a builtin change and its pin. **The compile canary
is the one that reports exactly the thing that is actually broken.** Prefer it;
do not grow both.

## Gate

T's own gate for tooling changes, plus: revert to `97b1812fe`'s tree state in a
scratch clone and confirm the new canary goes RED there, then green at the v369
pin. A canary that has never been seen to fail is not yet a canary.

## Resolved 2026-08-26 (pxx-aa, Track T)

`gate.sh` grows `pinned_rtl_canary()`: compile `test/test_uses_sysutils.pas`
with `stable_linux_amd64/default/pinned`. ~1s, compile only.

**Wired in ONE place, before the `case`, so it covers `quick`, `lib` and `full`
alike.** The first draft put a `step` line in each branch; a check that must be
remembered in every new mode is the check that will be missing from the next
one.

### The gate asked for a canary that has been seen to fail, so it was

Not by reverting a clone to `97b1812fe`, which is slower and no more faithful.
In a scratch tree (`pinned` + the frozen `builtin/` + a copy of `lib/rtl`,
laid out so `ExeDir/../lib/rtl` resolves), one injected reference in
`lib/rtl/sysutils.pas` to a builtin the frozen set does not define reproduces
the original error shape exactly:

```
pascal26:5306: error: undefined variable (PXXCanaryProofHook)
  in: ./stable_linux_amd64/default/../lib/rtl/sysutils.pas
  near: PXXNilRefHook   SysRaiseAccessViolation  PXXCanaryProofHook >>>
```

and through `gate.sh`'s own `step` wrapper it prints
`FAIL  pinned builds live lib/rtl` and returns 1, i.e. the gate goes RED.

### The hole the fix would otherwise have opened

The canary SKIPs when the fixture or the pin is absent — correct on a fresh
clone, and a **permanent silent green** in-repo if another lane ever renames
`test/test_uses_sysutils.pas`. That is the same failure this ticket is about,
one level up, and it is the third instance found today (the fgl rung guarded on
an absent `/usr/share/fpcsrc`; fpjson enrolled in no tier at all).

So `tools/gate_pinned_rtl_canary_devtest.py` asserts the fixture exists, still
contains `uses sysutils`, that gate.sh still defines and invokes the canary,
and — the real one — that the canary is green on a sound tree and red on an
injected mismatch. ~2s.

### Not done, deliberately

The reverse assertion the ticket floats (frozen `builtin/` byte-identical to
`compiler/builtin/` when the pin is current) stays unbuilt, for the reason the
ticket gives: it fires correctly but noisily on every Track A commit between a
builtin change and its pin. The compile canary reports the thing that is
actually broken. Do not grow both.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
