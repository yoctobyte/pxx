---
track: C
tags: [c, constant-folding, linker, dropbear, libtommath]
prio: 50
type: bug
blocked-by: []
summary: "A comparison of two integer literals was not folded to a literal in the C frontend, so `&&`/`||` short-circuiting (which only folds a literal left operand) kept the dead arm. libtommath's `if (MP_HAS(S_MP_TOOM_MUL) && ...) s_mp_toom_mul(...)` then referenced configured-out functions, and dropbear failed to link. Comparisons of two non-negative literals now fold."
status: done
owner: claude
---

# A literal comparison did not fold, so `&&` kept its dead arm

Found linking dropbear 2026.94 ([[feature-c-dropbear-builds-with-pxx]]):
`undefined reference to s_mp_toom_mul`, `s_mp_karatsuba_mul`,
`s_mp_toom_sqr` and `s_mp_karatsuba_sqr`.

**Cause.** libtommath configures itself with

```c
#define MP__STRINGIZE(x) ""#x""
#define MP_STRINGIZE(x)  MP__STRINGIZE(x)
#define MP_HAS(x)        (sizeof(MP_STRINGIZE(BN_##x##_C)) == 1u)
```

and `mp_mul`/`mp_sqr` pick an algorithm with
`if (MP_HAS(S_MP_TOOM_MUL) && (min_len >= MP_TOOM_MUL_CUTOFF))`. The
algorithms dropbear leaves out are not compiled at all, so gcc dropping the
dead arm (it does so at -O0) is what makes the program link.

pxx folded `sizeof` of the concatenated literal correctly (a runtime check
agreed with gcc), but `CMakeBinop` built `==` of two literals as a binop. The
`&&` short-circuit fold asks `CConstIntLit` about its left operand, saw a
binop, and kept the right arm. A bare `if (MP_HAS(X))` had always worked,
because the IR's constant-branch fold pruned it later. Only the `&&`/`||`
chain reached the linker.

**Fix.** In `compiler/cparser.inc` `CMakeBinop`, `== != < <= > >=` on two
integer literals now becomes a 0/1 literal. Both operands must be
non-negative, so C's signed/unsigned conversion cannot change the answer
(`-1 < 1u` stays a runtime compare with its CTrunc32 handling). `-OO` still
turns every fold off, through CConstIntLit.

**Test.** `test/c_literal_compare_folds_in_and_chain.c` (row `clitcmp26`).
It uses libtommath's MP_HAS verbatim in `&&`, `||`, `!=`, `<` and `?:`
chains. The functions on the dead arms are declared and never defined, so a
surviving call fails to link or load. The expected output is gcc -O0's.
