---
track: A
prio: 40
type: feature
blocked-by: []
summary: "Importing esp_sntp.h on riscv32/esp fails with 'C: inline asm with a non-empty template is only supported on x86-64 and i386, not riscv32'. IDF headers carry static inline helpers with riscv asm (CSR reads, fences: esp_cpu.h / riscv/rv_utils.h style) that an importing Pascal program usually never calls. Accept them at parse time and fail only if such a function is actually emitted (called), or support basic riscv32 inline asm. Measured 2026-10-05, frank-user master fe4e8acb2d."
status: done
owner: ""
---

# riscv32 C import: tolerate inline asm in uncalled static inline helpers

- **Type:** feature (C frontend, riscv32 inline asm) — **Track A**.
- **Filed:** 2026-10-05 from `~/museum_landkaart`, the ESP-IDF census.

## Repro

```sh
cd ~/museum_landkaart/async && tools/idf_census.sh esp_sntp
# esp_sntp: pascal26:86: error: C: inline asm with a non-empty template is only supported on x86-64 and i386, not riscv32
```
(the full message and location are in build/census/esp_sntp.txt)

## Why

A header import parses every static inline function in the chain. IDF's riscv
helpers use asm for CSRs, fences and wfi. The app (soft-AP, SNTP, NVS, RMT) never
calls them from Pascal. Option A, accept and poison: parse the asm and error only
if the function is reached by codegen. Option B: real riscv32 extended asm for the
common forms. A is enough for the demo.

## Acceptance

`tools/idf_census.sh esp_sntp` gets past the asm. A Pascal call to such a helper
gives a clear error (A) or works (B).

## Resolution (2026-10-05)

Accept-and-poison, as asked (ProcAsmPoison in defs.inc). Inside a routine of
an imported header (CHeaderMode), these are no longer errors: inline asm this
target cannot read, and a call to an undeclared function (`__builtin_ffs`
→ crtl's `__pxx_builtin_ffs32`, absent when newlib is the libc). The routine
is marked instead. Lowering a call to it refuses by name ("cannot call wrap:
its body holds C inline asm ..."). A header routine that calls a poisoned one
inherits the poison. The refusal sits ahead of IRInlineExpand, so it holds at
-O2. `__builtin_strrchr`/`strchr` over a literal now fold (IDF's
`__FILENAME__`). test-core rows: builtin_strrchr_fold, header_poison26.
