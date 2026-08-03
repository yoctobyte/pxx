---
track: P
prio: 30
type: feature
summary: "A routine directive that is accepted but cannot be honored is silently ignored — `iram` on x86-64, `inline` anywhere (the flag is written and never read), `register`, `cdecl` on a routine. Warn: 'directive ignored here', so the source stops claiming something the build does not do."
---

# Warn when a routine directive is accepted but cannot be honored

- **Type:** feature (Pascal frontend — diagnostics) — **Track P**
- **Opened:** 2026-08-03, from the user while documenting decorators:
  *"at worst, worth a warning 'you declared this decorator but it cannot be
  fulfilled' or 'its invalid/ignored/conflicting/overruled by calling
  convention'."*

## The situation

Routine directives fall into three groups today (measured, and now tabulated in
`docs/language/dialect.md#routine-directives`):

- **load-bearing** — `assembler`, `generator`, `async`, `stackless`,
  `interrupt`, `flexcolumn`, `external`, `virtual`/`override`/`abstract`,
  `static` on a class method;
- **accepted and ignored** — `cdecl`, `register`, `inline`, `stackful`,
  `reintroduce`, `static` on a plain routine, `iram` off the ESP targets, and
  the hint directives;
- **rejected** — `stdcall`, `safecall`, `pascal`, `mwpascal` outside a method
  declaration, and `varargs` anywhere
  ([[compat-pascal-calling-convention-directives-uneven]]).

Only `interrupt` says anything when it cannot be honored:

```
error: interrupt directive: raw hardware-vector codegen implemented for riscv32
(esp32c3) and xtensa Call0 (esp32s3) only. Use `iram;` for an IDF-registered ISR.
```

Everything else is silent. `iram` on x86-64 compiles clean. So does `cdecl` on a
routine — and there the silence is defensible (the convention is the target's,
so the marker is documentation) but a reader cannot tell the two cases apart.

## `inline` is the interesting one

`ProcInline` is **written and never read.** `if declInline then
ProcInline[procIdx] := True` in `parser.inc` is its only mention outside the
`False` initialiser in `symtab.inc`; no backend, IR pass or inliner consults it.
The `-O2` inliner decides purely on shape — a function, scalar result, at most
six scalar by-value params, not external/cdecl/variadic/generator/stackless.

Measured with `PXXDBG=a.inline` at `-O2` on a marked and an unmarked routine of
the same shape:

```
PXXDBG a.inline RETAIN twice  shape=1 params=1     { NO inline directive }
PXXDBG a.inline RETAIN thrice shape=1 params=1     { inline; }
```

Identical. So `inline` neither helps nor hurts, and a routine that does not
qualify is not inlined however loudly it is marked. That matches every modern
compiler — the directive is a hint and the optimizer already knows — but it
means a user writing `inline` on a six-parameter procedure returning a record is
being told nothing while getting nothing.

## Proposal

A single `warning: directive 'X' is ignored here` diagnostic, off by default or
under an existing strictness flag (`--strict-fpc`'s umbrella is the natural
home — see [[project_strict_fpc_umbrella_and_lax_default]]), covering:

- a target-conditional directive on a target that has no use for it (`iram`);
- a directive that is inert everywhere (`register`, `cdecl` on a routine) —
  message should say *why* ("the calling convention is the target's"), not just
  that it was dropped;
- `inline` on a routine the inliner cannot take, with the reason it failed the
  shape test. This is the one with real user value: it turns a silent no-op into
  "your routine is too big to inline, and here is which rule it broke".

Deliberately NOT proposed: warning on the hint directives
(`deprecated`/`platform`/…). Those are meant to be inert until usage warnings
exist, and warning about them would fire on ordinary FPC source.

## Gate

Each inert directive warns under the flag and stays silent without it; the
corpora and `lib/rtl` build with no new warnings in the default mode; self-host
fixedpoint byte-identical.
