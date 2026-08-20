---
track: C
prio: 60
type: bug
blocked-by: []
summary: "`tab[0](5, 6)` failed to PARSE when `tab` was a LOCAL typedef'd function-pointer array, and `s.f[i](args)` -- a dispatch table in a struct, the ordinary C vtable -- failed at any scope. Four neighbouring spellings of the same call worked, which is what hid both."
status: done
owner: frank1-ACP
---

# A function-pointer TABLE is not callable: local array, and struct field

- **Track C** (`compiler/cparser.inc` — the local array declaration path, and
  `CalleeSig`).
- Found 2026-08-20 by a gcc differential probe over C aggregates.

## The measurement

`gcc -O0` vs pxx at `d2eaf3f18`. Both failures are **parse errors**
(`error: unexpected token`), not wrong values.

| shape | gcc | pxx |
| --- | --- | --- |
| `binop tab[2] = {add,mul};` **inside a function**, then `tab[0](5,6)` | 11 | **parse error** |
| the same declaration at **file scope** | 11 | 11 |
| `int (*tab[2])(int,int)` (raw spelling), either scope | 11 | 11 |
| `binop g = tab[0]; g(5,6)` (via a temp) | 11 | 11 |
| `h.f[0](5,6)` — struct field array, local struct | 11 | **parse error** |
| `gh.f[0](5,6)` — global struct | 11 | **parse error** |
| `p->f[1](5,6)` | 30 | **parse error** |
| `(*h.f[0])(5,6)` | 11 | **parse error** |

Five ways to spell one call; the two that real code writes were the broken
ones. That is why this survived: every alternative worked, so any single test
would have passed.

## Two root causes

**1. The local array declaration never recorded the element signature.** The
scalar local branch sets `SymProcSig[idx] := declProcSig` for a plain
fn-pointer variable, and the file-scope path sets `SymElemProcSig` for an
array — but the LOCAL array branch set only the pointer metadata
(`PtrElemTk`, `PtrDepth`, …). With no `SymElemProcSig`, `CalleeSig`'s
`arr[i](args)` arm had no signature to bind and the `(` was unexpected.

The channel matters: `SymElemProcSig`, never `SymProcSig`. The file-scope arm
already says why — `SymProcSig` marks the array VARIABLE as a proc value, so
codegen resolves `tab` to a code address and the indexing is corrupt.

**2. `s.f[i](args)` was missing from `CalleeSig` entirely.** It has an arm for
`AN_INDEX` over an `AN_IDENT` (a plain array) and an arm for `AN_FIELD` (a
scalar fn-pointer field), but nothing for an `AN_INDEX` over an `AN_FIELD`.
A struct holding a dispatch table — how C spells a vtable, and what every
plugin/driver interface in C looks like — could not be called at all. The new
arm reads the field's per-element signature from `RecFieldElemProcSig`, the
same channel `(*s.pf)(args)` already uses, falling back to the field's own sig.

## Test

`test/cfnptr_array_callable.c`, gcc-oracled: the local table and the struct
field at both scopes and through `->`, a runtime index and a loop over one,
an explicit deref of the element, a table declared with no initializer and
filled afterwards, and every spelling that already worked (file scope, raw
declarator, temp, direct call, an ordinary non-pointer field) so the fix is
proved not to have moved them. The pinned binary cannot compile it.

## Not affected

The rest of the C probe matches gcc line for line: bitfields (including
truncation on overflow and signed narrow fields), unions and their byte/short
overlays, struct layout and offsets with and without `__attribute__((packed))`,
designated initializers (flat, nested, and array-index), the comma operator,
ternary result types, integer promotions and signed/unsigned comparison, and
switch fallthrough.

`__builtin_offsetof` is not recognised (the `&((T*)0)->m` form works); noted,
not filed — nothing depends on it here.

## Gate

`make compiler/pascal26` fixedpoint converged after 1 round; `tools/gate.sh
quick` GREEN.
