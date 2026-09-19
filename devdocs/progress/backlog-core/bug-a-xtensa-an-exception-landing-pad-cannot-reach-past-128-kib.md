---
track: A+S
prio: 55
type: bug
status: open
found: 2026-09-19
found-by: frankS
blocked-by: []
summary: "xtensa refuses any procedure whose exception-cleanup landing pad sits more than 128 KiB past the frame's entry branch: EmitProcCleanupFramePatchLanding patches a 3-byte `j` (imm18, +-128 KiB) and CheckProcCleanupBranchRange errors past that. riscv32/aarch64 have +-1 MB there and x86-64/i386 rel32. It springs on any single procedure body over 128 KiB that needs a cleanup frame -- today one in compiler/builtin/pyeval.pas (152,807 bytes, the proc ending just before PyFieldGet), which is what stops EVERY NilPy program building for ESP32-S3 under --platform=esp. The skip branch (EmitProcCleanupFrameSkipForTarget) is the same 3-byte `j` over the same span and needs the same answer. Fix shape: a long form for both, e.g. branch to a nearby stub that does an l32r/jx, as the entry stub already does for the 128 KiB main-body case (bug-a-xtensa-entry-jump-cannot-reach-a-main-body-past-128kb), valid under BOTH the windowed and the Call0 ABI."
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
