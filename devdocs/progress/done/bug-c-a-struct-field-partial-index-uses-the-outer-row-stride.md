---
track: C
prio: 65
type: bug
blocked-by: []
summary: "A PARTIAL index of a multi-dim struct FIELD was wrong twice over, silently: the decayed row pointer carried no stride so `*(s.m[1]+1)` stepped ONE BYTE (11 -> 184549376), and the offset multiplier was the OUTER row at every depth, so `s.m[1][2]` on `int m[2][3][4]` walked 48 bytes per unit instead of 16 and left the object. The bare-array spelling of both was already correct."
status: done
---

# A struct field's partial index uses the outer row stride, and stamps no stride at all

- **Type:** bug (silent wrong value) — **Track C**, `compiler/cparser.inc`.
- **Found:** 2026-08-29, while reading the two sentinel write sites for
  [[refactor-c-the-partial-index-sentinel-should-not-be-a-type-tag]]. Not
  reported by anything: the shape has **zero** test coverage (proven — see
  Gate).

## Measured (gcc oracle, `tools/gcc_diff_probe.sh`)

```c
struct S2 { int m[3][4]; } s;          /* filled m[i][j] = 10*i + j */
struct S3 { int m[2][3][4]; } t;       /* filled 100*i + 10*j + k   */
```

| expression | gcc | pxx (before) |
| --- | --- | --- |
| `*(s.m[1] + 1)` | 11 | **184549376** (= 11 shl 24) |
| `*(s.m[2] + 3)` | 23 | **5376** |
| `int *q = t.m[1][2]; q[0]` | 120 | **-2121552008** |
| `q[3]` | 123 | **32767** |

The last row is the loud one: the address had left the object entirely. The
same four expressions written against a bare `int m[3][4]` / `int m[2][3][4]`
were correct throughout — which is what says these are defects and not a
dialect choice.

## Two causes, both in the struct-field arm of `ParseCPostfixTail`

The array arm and the field arm build the same thing — `&base + flat*stride`
over a base retagged `tyInt64` — from two separate blocks. Each defect is the
field arm missing something the array arm does.

1. **No `ASTSLen` stamp on the add node.** Retagging the base `tyInt64` is
   what makes the add a raw byte add, and it is also what blinds
   `IRPointerStride`: neither operand is a pointer any more, so it falls to
   its size-1 default and the decayed row steps one byte. The builder is the
   only place that still knows the row's stride, so it must stamp it.
   [[bug-c-a-multidim-array-decays-with-the-element-stride]] found exactly this
   and fixed the ARRAY arm; the field arm was the sibling nobody grepped for.
   *(`normalise-dont-special-case.md`: "if you fix a bug on one arm of a double
   case, grep for the sibling before closing the ticket." Eight months later,
   here it is.)*

2. **`RecFieldRowStride` is the OUTER row, used at every depth.** That helper
   answers for ONE subscript — `elem * product(span[1..n-1])`. With `ndi`
   subscripts consumed the multiplier is the product of the *remaining* spans,
   which is what the array arm computes for itself. On `int m[2][3][4]`,
   `t.m[1][2]` therefore multiplied by 48 where 16 was right.

## Fix

Both in the struct-field partial-index arm, `compiler/cparser.inc`:

- Divide the inner spans back out of `RecFieldRowStride` to recover the element
  size, then multiply back the spans this partial index actually leaves. (Going
  through the helper rather than re-deriving the element size from the field
  type keeps the `tyRecord` case the helper already handles from needing a
  second implementation here.)
- Stamp `ASTSLen[inode]` with what the resulting row pointer steps by, the same
  way the array arm does.

## Gate — and what it proved about coverage

- `make compiler/pascal26` — `converged after 1 round(s)`.
- The 43-test C differential (named tests, sha256 of each binary) came back
  **43/43 byte-identical, no output change**. For a fix that changes emitted
  constants, that is not reassurance — it is **proof that no existing test
  reaches this shape at all**, which is why it survived.
- New regression `test/cfield_partial_index_stride.c`, wired into `test-core`:
  matches gcc after the fix, and was confirmed to FAIL on `pinned` before it,
  on exactly the three assertions above, with the bare-array columns beside
  them staying correct.

## Log
- 2026-08-29 — found, fixed, tested (frankC).
- 2026-08-30 — resolved, commit PENDING-COMMIT.
