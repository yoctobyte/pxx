---
track: C
prio: 50
type: bug
status: done
found: 2026-09-27
found-by: frankD
owner:
summary: "The condition of `if`, `while`, `for`, `do` and `?:` over a double or float tests the register bits, not the value: -0.0 is TRUE on every target; on i386 and arm32 `f ? 1 : 2`, `if ((t = f))` and 0.5 are wrong as well (0.5 reads false). `!`, `&&` and `||` were right. SILENT, same on v445 (caf21ac399f1)."
---

# A floating condition branches on its bits

```c
volatile double z = -0.0, h = 0.5;
z ? 1 : 2      /* every target: pxx 1, gcc 2 */
if (h) ...     /* i386, arm32: not taken */
```

Found by the cross-target differential, 2026-09-27.

## Resolution (2026-09-28)

`CCondOf` in compiler/cparser.inc wraps a floating condition in
`CMakeTruthy` (the `!= 0` compare `!`/`&&`/`||` already used) at the if, while,
for and ternary condition sites. Fixture
`test/c_a_floating_condition_tests_its_value.c` (29 rows incl. do/for forms,
float and NaN): v445 8-9 rows wrong per target, this build none.
