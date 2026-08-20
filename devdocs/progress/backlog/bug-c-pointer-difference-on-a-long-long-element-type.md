---
track: C
prio: 55
type: bug
blocked-by: []
summary: "Pointer difference is wrong for `long`/`long long` element types only: `q - p` answers 0 and `q - a` answers garbage, while char/short/int/float/double/void*/struct all answer correctly. The operands look like they are being read as VALUES rather than pointers."
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
