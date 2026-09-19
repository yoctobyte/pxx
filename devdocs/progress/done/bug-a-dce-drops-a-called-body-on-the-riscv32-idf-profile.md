---
track: A+S
prio: 45
type: bug
status: done
found: 2026-09-19
found-by: frankS
blocked-by: []
summary: "FIXED 2026-09-19. MECHANISM, and it is not riscv32's and not the ESP profile's: a body whose range holds a CodeRef stub target is KEPT by the pass (something jumps into it), but it was never MARKED live, so its outgoing calls were never followed. Its call sites then survive the compaction -- they are not inside a removed range -- while their callees are dropped, and ApplyCallFixups stops the build by name. A body that stays in the image and can be entered is code that RUNS, so DceRun now marks every stub-holding body as a root BEFORE the fixpoint; a decision taken after the fixpoint cannot feed it. What differs per target is only WHICH bodies end up kept-but-dead, which is why the same program built on x86-64 and xtensa and refused on riscv32. Guarded by test/test_dce_nilpy_esp_kept_body.npy in the test-esp-idf target, both ESP ISAs, build-only (this class stops the build rather than mis-running) with the shrink assertion beside it."
---

# DCE drops a called body on the riscv32 IDF profile

## Repro

```sh
printf 'class B:\n    def __init__(self, n):\n        self.n = n\ndef main():\n    print(B(3).n)\nmain()\n' > /tmp/d.npy
./compiler/pascal26 --dce --target=riscv32 --platform=esp -Fu$PWD/lib/rtl \
  -Fu$PWD/lib/rtl/platform/esp /tmp/d.npy /tmp/d.o
# pascal26:..: error: unresolved forward: PyUserObjGetattrTry
./compiler/pascal26 --dce /tmp/d.npy /tmp/d_x64            # builds
./compiler/pascal26 --dce --target=arm32 /tmp/d.npy /tmp/d_arm   # builds
./compiler/pascal26 --target=riscv32 --platform=esp -Fu$PWD/lib/rtl \
  -Fu$PWD/lib/rtl/platform/esp /tmp/d.npy /tmp/d.o       # builds (no --dce)
```

Measured on the full class/list demo (`examples/esp32/nilpy-c3/main/main.npy`)
2026-09-19; the reduced repro above is the same shape and is NOT separately
re-run -- run it before trusting it.

## Where to look first

`PyUserObjGetattrTry`'s body is a `try ... except on AttributeError do` block.
The two things that differ between the passing and failing cells are the
target (riscv32) and `--emit-obj`/`--platform=esp`, so the suspects are an
edge DCE's riscv32 reachability scan does not record (a call emitted through a
path that bypasses RecordInternalCall), or an exception-frame edge only this
profile emits. `bug-a-dce-refuses-every-target-except-x86-64` is the ticket
that turned DCE on for riscv32.

## Resolution (frankS, 2026-09-19)

The two callers are `pydynattr_hasattr` and `pydynattr_has_any_v`, and
`--dce-report` names them itself: `kept (holds a stub target)`. Both were dead,
both were kept whole, and both call `PyUserObjGetattrTry`, which nothing live
reaches. 71 bodies were kept that way on riscv32 in this program.

POSITIVE CONTROL, and NOT the pinned compiler: pin v412 predates the IDF heap
arena and refuses this program before DCE runs, so it fails for an unrelated
reason. The control is HEAD with the `DceMark` loop reverted -- riscv32 then
says `unresolved forward: PyUserObjGetattrTry` and xtensa still builds.

SIZES, same program, `examples/esp32/nilpy-{c3,s3}/main/main.npy`, measured
through `PXX_EXTRA_FLAGS=--dce ./build.sh qemu-assert`, flashed image (the
`.bin` esptool writes) and pxx's own `code=`:

| chip | image off | image on | code off | code on |
| --- | --- | --- | --- | --- |
| ESP32-C3 (riscv32) | 3,326,224 B | 2,307,648 B | 2,995,036 B | 2,074,596 B |
| ESP32-S3 (xtensa)  | 3,246,288 B | 1,996,848 B | 2,901,167 B | 1,741,723 B |

Both demos still RUN with `--dce`: output == CPython, one boot, on both chips.
Neither fits the stock 1 MB factory partition even so, so the 4 MB partition
table stays and the demos are still built WITHOUT `--dce` -- the flag is now
measurable against them (`PXX_EXTRA_FLAGS`), not default. What would change
that is the next row: DCE is worth 31% on riscv32 and 40% on xtensa here, and
1 MB needs 66%.

NOT closed by this ticket, banked as its own: riscv32 keeps 870 bodies live
against xtensa's 735 on the identical program, ~340 KB of code --
`bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program`.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 357d13162.
