---
summary: "C: `0 ? ((*(dst) = *(src)), 0) : 1` as an array size read the arm as 0 -- git's MOVE_ARRAY check failed as a static assert"
type: bug
prio: 40
---

# C: a comma or an assignment in a constant-expression arm is not read

- **Type:** bug (C frontend). Found 2026-11-27 building git 2.56.1 for the
  Nodisx git recipe (apply.c, line 371).
- **Status:** done

## Symptom

git checks MOVE_ARRAY's operands at compile time. pxx does not claim
`__GNUC__ >= 3` to git's GIT_GNUC_PREREQ, so the portable spelling is used:

```c
#define BUILD_ASSERT_OR_ZERO(cond) (sizeof(char [1 - 2*!(cond)]) - 1)
#define BARF_UNLESS_COPYABLE(dst, src) \
	BUILD_ASSERT_OR_ZERO(0 ? ((*(dst) = *(src)), 0) : \
				 sizeof(*(dst)) == sizeof(*(src)))
MOVE_ARRAY(img->line, img->line + 1, img->line_nr);
```

pxx: `C: array dimension is negative (-1) — a BUILD_BUG_ON/static-assert of
this shape is FAILING`. gcc compiles it (the bound is 1).

Smaller shapes, all wrong:

| dimension | gcc | pxx before |
|---|---|---|
| `1 - 2*!(0 ? (x = 1) : 1)` | 1 | -1, refused |
| `1 - 2*!(0 ? (1, 0) : 1)` | 1 | -1, refused |
| `1 ? 2 : (x = 1, 0)` | 2 | `expected ']'` |
| `(1, 3)` (a VLA bound) | 3 | `expected ']'` |

## Cause

The constant folder (CEvalConstPrimary) read a parenthesised expression with
CEvalConstExpr and stopped at the first token it had no rule for: an
assignment operator, a comma, a unary `*`, or a `.`/`->`/`[` after a
variable. The arm then read as 0. In a then-arm the `?:` took that 0. In an
else arm the leftover tokens were `expected ']'`.

## Fix

In CEvalConstPrimary:
- Inside parentheses, a `,` or any assignment operator continues the
  expression. The value is the last operand's, and the whole is marked
  run-time (CConstExprSawNonConst), as C says. A live one makes the
  dimension a VLA bound, as gcc does.
- Unary `*` reads its operand and is run-time.
- A declared variable's selectors (`.f`, `->f`, `[i]`) are read and are
  run-time.

CEvalConstDeadArm already drops the run-time mark for an arm a constant
condition does not take, so git's assertion folds to 1, as with gcc.

Test c_const_comma_assign_and_vla_sizeof (row c_ccav26), against gcc on
x86-64 and i386. It covers git's macros verbatim, MOVE_ARRAY moving the
bitfield struct, dead-arm shapes in both arms, file-scope dimensions, and live
comma and assignment bounds. The same test covers
bug-c-sizeof-of-a-vla-without-parentheses-is-the-pointer-size, found here.
