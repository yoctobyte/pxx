---
track: T
prio: 65
type: bug
blocked-by: []
summary: "A Track A change that adds a builtin and uses it from lib/rtl breaks every $(PXX_STABLE) build the moment it lands, because stable_linux_amd64/default/builtin/ is a FROZEN copy — and gate.sh quick is green through it, because the quick gate never builds anything with the pinned binary. It happened on 2026-08-21 and Track B/D/E were dead on master until the next pin. A ~1s canary closes it."
status: backlog
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
