---
track: A
tags: [C]
prio: 50
type: bug
blocked-by: []
summary: "`static long g = -17 >> 2;` is 4611686018427387899 where gcc says -5. The file-scope token evaluator (CEvalConstShift) uses Pascal's logical `shr` on Int64 and tracks no types, so a signed negative left operand of a 64-bit initialiser shifts in zeros. An `int` global truncates the result back to -5, and block-scope code goes through CMakeBinop's signed/unsigned pick, so both are right."
status: open
owner: unassigned
---

# A file-scope constant right shift of a negative value is logical

Found while writing the Gibux static-data test on 2026-11-12:

    static long g1 = -17 >> 2;     /* gcc -5, pxx 4611686018427387899 */
    static int  g3 = -17 >> 2;     /* -5 in both: the store keeps 32 bits */
    long l1 = -17 >> 2;            /* block scope: -5 in both */

`CEvalConstShift` in cparser.inc folds `>>` with `shr`, which is logical on
Int64. The evaluator carries values, not types. Making it arithmetic would
break the other common spelling, `~0ull >> 4` or `~0UL >> 1`, which must be
logical. A correct fix has to carry signedness through the token evaluator:

- the `u` suffix;
- casts;
- the usual arithmetic conversions.

Alternatively, the initialiser could be evaluated from the typed AST, where
CMakeBinop already makes this choice (tkShr vs tkShrLogical).

Not a regression: the pinned compiler gives the same value.
