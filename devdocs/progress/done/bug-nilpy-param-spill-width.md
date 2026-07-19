---
track: N
prio: 60
type: bug
---

# NilPy: bool/char param spill wrote 4 bytes into a 1-byte slot (SILENT, then SIGSEGV)

Pre-existing: the hand-rolled NilPy prologue spilled every param with a
dword/qword store regardless of slot size. A tyBoolean param slot is 1 byte,
so the store clobbered up to 3 bytes of the neighbouring slots: bool params
read back wrong (True -> False), and with more params the clobber reached
self and crashed. `class J: def __init__(self, p: bool)` was enough.

Fixed with PyEmitStoreRaxWidth (width by TypeSize) in the same unit as
feature-nilpy-decorators-dataclass / feature-nilpy-def-params.
