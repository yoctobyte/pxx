---
track: A+S
prio: 55
type: bug
status: done
found: 2026-09-19
found-by: frankS
blocked-by: []
summary: "FIXED 2026-09-19. On xtensa every profile except BARE now enters a proc cleanup frame's landing pad through the reach-independent long jump (EmitXtensaLongJumpSlot: call0-as-PC anchor, .text-offset delta in a literal, jx), sitting on the exceptional edge only -- the normal return's beq skips it, so the cost is flash bytes per cleanup frame, never time. Bare keeps the 3-byte `j`, as the entry stub does. Only the ENTRY branch spans the body; the SKIP branch spans the pad and needed nothing (this summary said otherwise when filed)."
---

# xtensa: an exception landing pad cannot reach past 128 KiB

## Repro (at `fe2d955b4`+ tonight's ESP changes)

```sh
cat > /tmp/app.npy <<'PY'
class Boat:
    def __init__(self, name, speed):
        self.name = name
        self.speed = speed
def main():
    print(Boat("a", 3).name)
main()
PY
./compiler/pascal26 --target=xtensa --xtensa-abi=windowed --platform=esp \
  -Fu$PWD/lib/rtl -Fu$PWD/lib/rtl/platform/esp /tmp/app.npy /tmp/app.o
# pascal26:1722: error: proc exception cleanup frame: body too large for the
#   landing-pad branch on this target (152807 bytes)  in ./compiler/builtin/pyeval.pas
```

It is the third wall on this route, measured in order: the IDF heap arena
(fixed), `ParamStr` refused on ESP (fixed), then this. The esp32c3 route, same
program, builds and runs (`examples/esp32/nilpy-c3`).

## Where

`compiler/ir_codegen.inc`: `EmitProcCleanupFrameForTarget` (xtensa arm ends in
`landPatch := CodeLen; xtensa_j(4)`), `EmitProcCleanupFramePatchLanding`
(`CheckProcCleanupBranchRange(..., 131072)`), and
`EmitProcCleanupFrameSkipForTarget` (`xtensa_j(4)` again).

Not the call-reach question of
`feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image`: that is a
CALL across the image; this is a BRANCH inside one procedure.

## Resolution (2026-09-19, frankS)

`XtensaCleanupLandingIsLong` (ir_codegen.inc) decides the width up front,
per profile, because the entry branch is emitted before the body exists and
patched after it -- it can never be widened in place, and the IR body's
relaxation never sees it. The literal parks the anchor PC until the pad lands;
`EmitProcCleanupFramePatchLanding` reads it back and writes the delta.

The filed summary said the skip branch "needs the same answer". It does not:
`EmitProcCleanupLandingPadForTarget` emits the skip AFTER the body, over the
pad only. `CheckProcCleanupBranchRange`'s comment said the same thing and was
corrected in the same change.

Verified: the NilPy class/list demo now compiles for esp32s3 past this wall
(the next one is the windowed 22-argument-word limit, on the p85 ticket);
test-xtensa, test-esp-idf, test-esp-bare and gate quick green. Inert until the
next pin for anything built with `$(PXX_STABLE)`.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b4a92ea58.
