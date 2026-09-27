---
track: C
prio: 45
type: bug
status: done
found: 2026-09-27
found-by: frankD
owner:
summary: "CHAR_MIN/CHAR_MAX are -128/127 on every target, but plain char is unsigned on aarch64, arm32 and riscv32 (gcc 0/255). Also UCHAR_MAX, USHRT_MAX, UINT8_MAX and UINT16_MAX carry a U suffix C does not give them, so `-1 < UCHAR_MAX` is 0 (gcc 1) everywhere. SILENT, same on v445."
---

# CHAR_MIN and CHAR_MAX ignore the target's char signedness

Found by the cross-target differential, 2026-09-27 (crtl_libc_oracle row
`CHAR_MIN=-128 CHAR_MAX=127 char-signed=0` on aarch64/arm32/riscv32).

## Resolution (2026-09-28)

The preprocessor predefines `__CHAR_UNSIGNED__` where `CPlainCharSigned` is
false, as gcc does; lib/crtl/include/limits.h keys CHAR_MIN/CHAR_MAX on it.
UCHAR_MAX and USHRT_MAX (limits.h) and UINT8_MAX and UINT16_MAX (stdint.h)
are plain int constants. Fixture `test/c_limits_follow_the_targets_char.c`
(17 rows stated as rules): v445 5 rows wrong on the unsigned-char targets,
and 4 on every target with the old headers; this build none.
