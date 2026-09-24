---
track: A
prio: 20
type: feature
status: done
---

# Promotable int in a Variant: riscv32 / xtensa

**CLOSED BY EVENTS, 2026-09-24 (frankB).** The gate below is met at HEAD
(compiler af40370a8a91): `test/test_promoint.pas`, Variant section included,
prints output byte-identical to x86-64 on esp32c3 (`--target=riscv32
--platform=esp`) and esp32s3 (`--target=xtensa --xtensa-abi=windowed
--platform=esp`), 35 lines each, run with `tools/esp_run.sh` under Espressif QEMU.
Neither wall quoted below reproduces. Also compiles with no `--platform`
(bare/hosted), and linux riscv32 under qemu matches x86-64. No pin dependence
in the closure itself: nothing changed in the source; this only records the
measurement.

Separate finding, not this ticket's: a NilPy program on the ESP IDF profile
costs ~890 KB of code before it does anything (`print("hi")`: 889,804 B riscv32,
817,439 B xtensa), so the NilPy promo demo does not fit `examples/esp32/hello-c3`'s
1 MB factory partition. Promo is not the cause: an int accumulator adds ~8 KB
(897,932 B). The runtime-size mechanism is already recorded under
[[feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image]] (no DCE on
the IDF profile yet); `examples/esp32/nilpy-s3` is the project built for it.

Split from [[feature-a-promoint-32bit-bringup]]. The promotable int's own
arithmetic works on riscv32 (byte-identical to x86-64); only the VARIANT interop
does not build there, and for reasons that are not promo's.

## What fails

```
--target=riscv32 : error: target riscv32: write of this type not supported (hosted)
--target=xtensa  : error: compiler error: __pxx_d2i not found (uses softfloat?)
```

The riscv32 one is `Writeln` of a Variant — pre-existing, nothing to do with the
promotable int. The xtensa one is a softfloat entry point pulled in by the
variant runtime.

## Note the priority

Deliberately low. The umbrella ticket's reason for caring about these targets is
`promo32` on ESP for NilPy, and the promo CORE already works there — it is the
Variant tier that does not, which matters only once NilPy's soft-typed values
land on ESP. Do not confuse this with the core being broken.

## Gate

`test_promoint.pas` (the full one, including its Variant section) compiling and
matching x86-64 output on riscv32 and xtensa.

## Note 2026-08-02 — the xtensa half is a LINK gap, not a missing helper

`--target=xtensa : compiler error: __pxx_d2i not found (uses softfloat?)` reads
like an unimplemented conversion. It is not:

- `__pxx_d2i` **is implemented**, in `compiler/builtin/softfloat.pas:49`
  (alongside `__pxx_i2d`, `__pxx_d2i64`, `__pxx_d2i64_rne`).
- The xtensa backend **already calls it** —
  `ir_codegen_xtensa.inc:1665-1666` emits `__pxx_d2i` / `__pxx_d2i_rne`
  through `EmitFloatUnaryCallXtensa`.

So both ends exist and the symbol simply is not resolved in this build
configuration: the softfloat unit is not pulled in when Variant interop needs it
on xtensa. That makes this a unit-inclusion question rather than a codegen
feature, and likely much smaller than the error text suggests.

(Recorded while assessing what genuinely blocks xtensa now that the user has
made it the primary ESP target — see
[[feature-xtensa-stack-args-over-6-words]].)

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted — but the riscv32 half now fails DIFFERENTLY,
so the ticket's quoted error is stale.** Re-measured by compiling
`test/test_promoint.pas` with the pinned compiler:

| target | ticket's error (2026-07-20) | v363 |
| --- | --- | --- |
| riscv32 | `write of this type not supported (hosted)` | `pascal26:1605: error: target riscv32: standard builtin calls not supported in bare-metal stage 1 (builtin id 999)` |
| xtensa | `compiler error: __pxx_d2i not found (uses softfloat?)` | unchanged |

The riscv32 wall has moved from the Variant *write* path to a builtin-call
restriction, which is a different diagnosis from the one the ticket carries;
re-diagnose before estimating it. The xtensa half stands exactly as the
2026-08-02 note describes it — a unit-inclusion gap, not a missing helper.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
