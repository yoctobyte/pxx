---
track: A+S
prio: 20
type: feature
status: open
found: 2026-08-30
found-by: claude-A
---

# Make `uses builtin;` compile on a bare ESP boot

Today it does not, and that is the **documented, intended** state:
`(not TargetIsEspClass)` on 22 arms of `needsBuiltin` is the honest constraint,
and [[bug-a-builtin-pas-calls-a-declaration-that-esp-compiles-out]] closed as
working-as-intended on that basis. This ticket exists so the *option* survives
that closure instead of being lost with it.

## Why it is a feature and not a bug fix

Making it compile is not a repair with a known endpoint. It is an **open-ended
sequence of judgement calls about what the bare profile offers**, measured four
steps deep and still going:

```
step 0   undefined PXXVarBinOp (1148), undefined PxxSciDigits17 (1702)
step 1   guard those two      -> __pxx_d2i_rne not linked   (1235, VariantToDouble)
step 2   guard the Variant* group -> __pxx_dcmp not linked  (1586)
step 3   ...
```

Identical on bare riscv32, line for line — a **profile** property, not an ISA
one. Each guard exposes the next, and each step decides whether a feature
(variant arithmetic, float formatting, float comparison) belongs on a target
whose whole campaign is size. That is design work, and it is why this cannot
ride a bug ticket.

## What is already known, so nobody re-derives it

- `PXX_ESP` is **not** a compiler symbol; `PXX_ESP_BARE` is. `builtinheap.pas:18`
  converts one to the other *for that unit only*. Any new guard in another unit
  must define it itself or use `PXX_ESP_BARE` directly.
- `builtin.pas`'s three inert `{$ifndef PXX_ESP}` regions were **deleted** in
  `fccdc4671`, so there is no half-working scaffolding left to build on.
- The `uses softfloat` remedy the kernel diagnostic advises **does not work** —
  [[bug-a-the-no-fpu-diagnostic-advises-uses-softfloat-which-does-not-help]].
  Resolving that is probably a prerequisite, since several steps end in a kernel
  refusal rather than a missing declaration.
- Probing method that costs nothing: copy `compiler/builtin` and the `pascal26`
  binary into a scratch directory and iterate there. The compiler resolves its
  builtin tree relative to **the binary's own directory**, not the cwd, so this
  needs no pin and no repo edit.

## The measure to apply

`root-cause-over-microfix` says count tickets closed per change. Nobody has yet
named a program that wants `uses builtin;` on a bare boot. **Rank it against
that**, not against how close it looks.
