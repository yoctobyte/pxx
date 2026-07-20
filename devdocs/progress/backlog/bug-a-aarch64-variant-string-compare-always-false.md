---
track: A
prio: 70
type: bug
---

# aarch64: comparing two string-valued Variants is always FALSE

Found while regression-testing the promotable int's variant fallback path
2026-07-20. **Pre-existing and promo-independent** — the repro contains no
promotable int and does not load its runtime.

## Repro

```pascal
program p;
var v, w: Variant;
begin
  v := 'ab'; w := 'cd';
  Writeln(v < w);
  Writeln(v > w);
end.
```

| target | `v < w` | `v > w` |
| --- | --- | --- |
| x86-64 | TRUE | FALSE |
| aarch64 (qemu) | **FALSE** | FALSE |

Both orderings report FALSE, so the comparison is not merely inverted — the
string branch of the aarch64 variant compare never produces an ordering. `=`
and `<>` are worth checking in the same pass; only `<` and `>` were measured.

## Why it matters

It is a silent wrong ANSWER, not a crash, in a construct that looks obviously
correct. Any aarch64 code sorting or ordering variant-held strings is affected —
which includes NilPy, where values commonly live in variants and string
comparison is ordinary Python.

## Where to look

The variant binop is hand-written per backend. On x86-64 the ordering path is in
`EmitVarBinOp` (`ir_codegen.inc`), which has an explicit string branch reached
via the `VT_STRING`/`VT_CHAR` tag tests. Compare that against the aarch64
equivalent and establish whether the string branch is missing, mis-encoded, or
falling through to the numeric path (which, comparing two heap POINTERS, would
give an arbitrary but consistent answer — matching "always FALSE" here).

## Gate

The repro above matching x86-64 on aarch64, plus `=`/`<>`/`<=`/`>=` and a
char-vs-string mix; `--tier quick` + self-host byte-identical + cross. Check
arm32/riscv32 for the same shape.
