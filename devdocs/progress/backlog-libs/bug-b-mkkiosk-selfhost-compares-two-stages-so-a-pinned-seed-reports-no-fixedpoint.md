---
track: B
prio: 50
type: bug
status: open
found: 2026-09-10
found-by: frankD
owner: ""
blocked-by: []
summary: "`tools/mkkiosk.sh --selfhost` decides the in-VM fixedpoint by comparing stage1 against stage2, which converges ONLY when the seed compiler already matches the sources being built. Seeded with $(PXX_STABLE) -- which is the convention this lane's own rule prescribes -- it prints `NO FIXEDPOINT: stage1 != stage2` on a tree whose fixedpoint is fine. Measured 2026-09-10 at 32fb438eb: the same chain on the host converges one round later, stage2 == stage3 byte-identical (sha256 fe40bf55e1412ba5, 8140060 bytes) against stage1's 11969660. NOT a compiler defect and nothing to fix in compiler/**; the check needs a third round (or to state its seed precondition and refuse an old one). THE FAILURE MESSAGE IS THE ACTUAL COST: `NO FIXEDPOINT` on the project's headline property reads as a self-host regression, and it is what a reader following the docs' own recommended compiler will see."
---

# `mkkiosk --selfhost`'s two-stage check cannot converge from an older seed

Found while verifying the self-host claim for Track D's beta-0.1
minimal-Linux-system page, rather than citing a ticket for it.

## What happens

```
KIOSK_WORK=… PXX=stable_linux_amd64/default/pinned tools/mkkiosk.sh --selfhost

  === pxx kiosk: kernel 6.12.81-0-virt on x86_64 ===
  ok: ./pascal26.stage1  [code=11411224B  data=558204B  bss=86528492B  procs=4648]
  ok: ./pascal26.stage2  [code=7581464B   data=558364B  bss=86531564B  procs=4648]
  NO FIXEDPOINT: stage1 != stage2
```

The guest is right that the two differ, and wrong to call it a missing
fixedpoint. `stage1` is *HEAD's sources compiled by the pin's codegen*; `stage2`
is *HEAD's sources compiled by HEAD's codegen*. They cannot match while the pin
and HEAD disagree about codegen, which is most of the time and is the normal
state of a pin.

## The same chain on the host, one round further

`PXX_HOME=/home/neo/frankD`, stages outside the repo, 2026-09-10 at `32fb438eb`:

| stage | built by | sha256 | bytes |
| --- | --- | --- | --- |
| s1 | the pin | `a7865d584783cfd9` | 11,969,660 |
| s2 | s1 | `fe40bf55e1412ba5` | 8,140,060 |
| s3 | s2 | `fe40bf55e1412ba5` | 8,140,060 |

`cmp s2 s3` is equal. **The fixedpoint is reached at round 3 and the tree is
fine** — this is exactly the `converged after N round(s)` behaviour `make` reports
and the reason it counts rounds instead of assuming two.

The host `s1` code size (11,411,224) equals the guest's `stage1` exactly, so the
guest chain and the host chain are the same computation and the guest is not
doing anything special.

## Why it matters more than a demo script usually would

1. **It contradicts this lane's own convention.** `CLAUDE.md` tells B and E to
   build with `$(PXX_STABLE)` and not to rebuild the compiler. Do that here and
   the tool reports the project's headline property as broken. `mkkiosk.sh`
   defaults `PXX=compiler/pascal26`, so the working path is the one that ignores
   the convention, and the documented path is the one that fails.
2. **The message names the scariest possible cause.** `NO FIXEDPOINT` on a
   self-hosting compiler reads as a miscompile, not as a seed mismatch. This is
   the same class as the `gate.sh quick` red that `CLAUDE.md` already documents
   at length — *two valid fixedpoints, not a miscompile* — and the same remedy
   applies: say which chain was measured.
3. **It was cited in public docs.** `docs/examples/minimal-linux-system.md`
   pointed a reader at `--selfhost` as the place the fixedpoint is proved. The
   page now carries the seed precondition and the numbers above; without them a
   reader reproduces a false alarm.

## Fix shapes, cheapest first

- **Add a third round** and require `stage2 == stage3`. Matches `make`'s own
  definition, costs one more in-VM compile (~15 s of the 45 s run), and makes the
  tool seed-independent. Preferred.
- **Or state and enforce the precondition:** if `$PXX` is not the current tree's
  own compiler, say so up front and either refuse or downgrade the verdict to
  "not a fixedpoint check". A tool that cannot pass from the seed the rules
  prescribe should not report a failure that looks like a defect.

Either way the verdict line should name the seed it was measured from, so the
green means something a reader can reproduce.

**Positive control for the fix:** with `PXX=` the pin, the run must reach a
fixedpoint (at round 3) rather than print `NO FIXEDPOINT`. With `PXX=` a
current compiler it must still converge, and the round count should differ
between the two — if it does not, the third round is not actually running.
