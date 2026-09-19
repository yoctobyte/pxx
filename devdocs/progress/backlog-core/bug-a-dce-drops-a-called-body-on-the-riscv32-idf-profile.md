---
track: A+S
prio: 45
type: bug
status: open
found: 2026-09-19
found-by: frankS
blocked-by: []
summary: "`--dce` on riscv32 --platform=esp drops a body that a surviving call still targets: a NilPy program fails at ApplyCallFixups with `unresolved forward: PyUserObjGetattrTry` (compiler/builtin/pylib.pas: a try/except wrapper, called from two places in pylib). The same program builds with --dce on x86-64 and arm32, and builds WITHOUT --dce on riscv32 IDF, so it is DCE's live set missing an edge on this target/profile, not a pylib defect. Cost: NilPy on an ESP32-C3 is ~3 MB of flash without DCE, which is why examples/esp32/nilpy-c3 needs its own 4 MB partition table; DCE took x86-64 code 1.35 MB -> 0.76 MB on the same program."
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
