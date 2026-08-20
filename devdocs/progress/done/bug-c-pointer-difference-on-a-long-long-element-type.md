---
track: C
prio: 55
type: bug
blocked-by: []
summary: "Pointer difference is wrong for `long`/`long long` element types only: `q - p` answers 0 and `q - a` answers garbage, while char/short/int/float/double/void*/struct all answer correctly. The operands look like they are being read as VALUES rather than pointers."
status: done
owner: frank1-ACP
---

# Pointer difference on a `long long *` answers 0

- **Track C** (C frontend / pointer arithmetic lowering).
- Found 2026-08-20 beside
  [[bug-c-quickjs-runner-segfaults-with-zero-output-on-the-full-smoke-js]] —
  the probe that measured `p - buf` to prove the post-increment fix also
  measured it for every element type, and two of them were wrong.

## Measured — `ty a[8]; ty *p = a, *q = a + 3;`

| element type | `q - p` | `q - a` | gcc |
| --- | ---: | ---: | ---: |
| char | 3 | 3 | 3 |
| short | 3 | 3 | 3 |
| int | 3 | 3 | 3 |
| **long** | **0** | **-388852477** | 3 |
| **long long** | **0** | **-388851917** | 3 |
| float | 3 | 3 | 3 |
| double | 3 | 3 | 3 |
| void * | 3 | 3 | 3 |
| struct {int} | 3 | 3 | 3 |
| struct {long long,long long} | 3 | 3 | 3 |

So it is not about SIZE — `double` and `void *` are 8 bytes and correct, and a
16-byte struct is correct. It is the two 8-byte **integer** element types, i.e.
`tyInt64`.

## Reading of the numbers

`q - p` giving **0** and `q - a` giving a large negative both fall out of one
guess: the operands are being read as VALUES rather than as pointers.
`*q - *p` on a fresh (zeroed) stack array is 0, and `*q - &a[0]` is
`0 - <address>`, which is exactly the shape of the garbage. Worth confirming
with `PXXDBG=a.ir:main` before acting on it — a load_mem on the operands would
settle it in one look.

Likely mechanism to check first: a `long long *` whose pointee kind is tyInt64
losing its pointer-ness somewhere in the binop typing, so the subtraction is
classified as ordinary 64-bit integer arithmetic on the pointed-to type rather
than as pointer difference.

## Why the priority

Pointer difference over an array of 64-bit integers is everywhere in real C —
buffer length arithmetic, `end - begin` in parsers, bignum limb code. The
answer is silently wrong, not a crash. quickjs itself survives it only because
its own stack is `JSValue *`, a struct.

## Gate

The table above matching gcc row for row, as a new C pointer-difference test
verified against gcc; C tests green + self-host byte-identical.

---

## FIXED 2026-08-20 (frank1-ACP)

The guess in "Reading of the numbers" above was **wrong**, and measuring beat
it: nothing was being dereferenced. `q - p` answered 0 because the ADDRESSES
were only three bytes apart — `long long *q = a + 3` had advanced the pointer by
3 bytes rather than 24. The difference was then a correct division of a wrong
subtraction.

So the defect is in **pointer arithmetic**, not in pointer difference, and the
one-line probe that settled it was printing `(char*)(z+1) - (char*)z` per
element type:

| element | decay step, pxx | gcc |
| --- | ---: | ---: |
| char / short / int / unsigned | 1 / 2 / 4 / 4 | same |
| **long** | **1** | 8 |
| unsigned long | 8 | 8 |
| **long long** | **1** | 8 |
| unsigned long long | 8 | 8 |
| float / double / void * | 4 / 8 / 8 | same |
| struct{int} / struct{2×long long} | 4 / 16 | same |

**A sign bit decided a stride.** Indexing was always right — `a[1]` scales
itself — so the layout looked fine and only the decayed form was wrong.

### Root cause: a type tag doing duty as a flag

`IRNodePointerBase` carried a blanket bail:

```pascal
if CProgramMode and not Result and (IntToTypeKind(ASTTk[node]) <> tyInt64) then
  Result := CNodeDecaysToPointer(node);
```

An AN_IDENT for `long long a[8]` carries tyInt64 — its ELEMENT kind — so the
array was never a pointer base and `a + 1` fell through to a plain integer add.

The bail was not gratuitous, which is why deleting it broke two tests
immediately (`carr2d_decay_stride`, `cfield_2d_row_decay_b62`): cparser's
partial-index builder RETAGS its base `ASTTk[base] := Ord(tyInt64)` as a
**sentinel** meaning "this add is raw bytes, already scaled — do not scale me
again". tyInt64 therefore has two readings on a C node and the blanket test
could only honour one.

The fix asks whether the node's own DECLARATION explains the tag: a
fixed-extent, single-dimension array whose element type really is tyInt64
carries it honestly and decays like any other array; everything else keeps the
bail, which is what the multi-dimensional row cases need. The sentinel itself
borrowing a type field is filed as
[[refactor-c-the-partial-index-sentinel-should-not-be-a-type-tag]].

### Method note

Both the ticket's own guess and the `q - p` framing were dead ends. What
answered it was widening the MEASUREMENT — one row per element type, plus a
`(char*)` cast to see raw bytes instead of a scaled difference — rather than
reasoning about which lowering was to blame. The signed/unsigned split in the
table is what named the guard.

### Test

`test/cptrdiff_elem_types.c` — decay stride, `q - p`, `q - array` and the
element stride for twelve element types, plus globals, `+=`/`++`/`&a[i]`, and a
pointer walk that must visit every element. Verified against gcc on the same
source; wired into the Makefile beside `carr2d_decay_stride.c`, which pins the
sentinel reading of the same tag. The two together are what the tag has to keep
apart.

quickjs's smoke stays byte-exact, and the ten pointer/array C tests named one by
one during the work are green.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
