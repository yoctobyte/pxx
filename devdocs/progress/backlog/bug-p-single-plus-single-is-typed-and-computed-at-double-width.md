---
slug: bug-p-single-plus-single-is-typed-and-computed-at-double-width
track: P
prio: 40
type: bug
status: new
owner: ""
blocked-by: []
summary: "Pascal `Single + Single` is TYPED Double and computed at double width. `SizeOf(a + b)` answers 8 where FPC answers 4, and `d := a + b` for a=0.1, b=0.2 gives 0.300000004 where FPC gives 0.300000012. This is a strictly LARGER defect than the C one fixed in the same construct: C's binop node was already tagged tySingle and only its evaluation width was wrong, so one CNarrowSingle call at the tagging site fixed it. Pascal's node carries the wrong TYPE, so the same fix cannot be copied -- the type rule has to be settled first, and it decides whether SizeOf changing from 8 to 4 is acceptable. NOT Track F: the mechanism is which width an operator evaluates at, which is a type rule. Rank the mechanism, never the datatype."
---

# Pascal `Single + Single` is typed Double

- **Found:** 2026-08-30 by frankA, as the cross-frontend control while fixing
  `bug-c-float-plus-float-is-computed-at-double-width`. The Pascal run was the
  row that was supposed to be *unaffected*.
- **Pre-existing**, not a regression from that fix: the C change touches
  `cparser.inc` only.

## Measured, FPC as oracle

```pascal
var a, b: Single; d: Double;
begin
  a := 0.1; b := 0.2; d := a + b;
  WriteLn(d:0:9);
  WriteLn(SizeOf(a + b));
end.
```

| | pxx | fpc `-Mobjfpc` |
| --- | --- | --- |
| `d := a + b` | `0.300000004` | `0.300000012` |
| `SizeOf(a + b)` | `8` | `4` |

`0.300000012` is the single sum; `0.300000004` is the double sum widened.

## Why the C fix does not port

The C ticket's own summary is the discriminator, and it is worth stating because
the two look like one defect:

- **C:** `sizeof(1.0f+1.0f)` was already **4**. The node's static type was
  right and only its *evaluation width* was wrong, so one `CNarrowSingle` call
  at the single site that tags a binop `tySingle` fixed every shape.
- **Pascal:** `SizeOf(a+b)` is **8**. The node is typed **Double**. Narrowing a
  node that claims to be a double is not the same change, and doing it would
  make the type and the value disagree in the other direction.

So the first question here is the TYPE RULE, not the width. Settle what
`Single + Single` should be typed as, and check what depends on the current
answer before changing `SizeOf` from 8 to 4 — that is an observable a program
can branch on.

## Not started

Filed with the measurement only. The C half is fixed and tested
(`test/c_float_arith_at_single_width.c`, gcc oracle, 17 rows, verified
byte-identical on x86-64, i386, aarch64, arm32 and riscv32).

## Related

- `bug-c-float-plus-float-is-computed-at-double-width` — the C half, fixed.
- `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` — the two
  frontends are *supposed* to answer this separately; that they answer it
  differently is not itself the defect, the wrong answer is.
