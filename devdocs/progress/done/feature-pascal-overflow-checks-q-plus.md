---
summary: "{$Q+} overflow-checked integer arithmetic (Runtime error 215 / EIntOverflow) — the sole tint642 residual, also gates tint643"
type: feature
prio: 45
---

# {$Q+} / {$OVERFLOWCHECKS ON}: checked integer arithmetic

- **Type:** feature (FPC-parity runtime checks). **Track A** (lexer directive,
  parser tagging, per-backend check emission, RTL hook).
- **Status:** done
- **Opened:** 2026-07-14 night session, out of the tint642 burn-down: after
  record-cast offsets, bitwise not, u64→double and qword-literal domain all
  landed, `testreqword` ({$Q+} qword wrap must raise) is tint642's ONLY
  remaining red section. tint643 needs the same plus `on eintoverflow do`
  without a variable name (that parser gap is part of this ticket's
  acceptance).

## Semantics (FPC)

Inside a `{$Q+}` region, +, -, *, Succ, Pred, Abs and Sqr on integer operands
that wrap raise "Runtime error 215" — catchable as EIntOverflow when sysutils
is in. `{$Q-}` (default) keeps today's wrapping behaviour. The check is per
OPERATION SITE, lexically scoped by the directive.

## Design notes (from tonight's recon)

- **Directive plumbing:** the per-token pattern already exists —
  `TokPackRecords[TokPos]` carries `{$PACKRECORDS}` state per token. Mirror it
  (a per-token flag or a compact region list) for Q-state so the PARSER can ask
  "was {$Q+} active at this token?" — a single global boolean set during lexing
  is wrong (tint642 flips {$Q+}/{$Q-} between sections).
- **AST/IR carry:** IR_BINOP's `ival` is unused (0) for arithmetic — tag
  checked ops there (the IR_STORE_MEM string-capacity trick from
  bug-pascal-shortstring-no-truncation-buffer-overrun used the same free slot).
  On the AST side prefer a parallel node array with an Alloc* reset (see the
  symtab Alloc-parallel-array landmine) or fold the flag into the op encoding.
- **Runtime:** mirror the div-zero design exactly —
  `PXXOverflow` + `PXXOverflowHook` in builtinheap
  (`writeln('Runtime error 215 (arithmetic overflow)'); Halt(215)`), sysutils
  installs a hook that raises EIntOverflow, same as PXXDivZeroHook.
- **x86-64 emission:** signed add/sub/mul → `jo`; unsigned add → `jc`;
  unsigned sub → `jc` (borrow); unsigned mul → `jo/jc` of `mul`. 64-bit and
  subword both need the check at the RESULT width (subword results are
  computed in 64-bit registers — check against the declared width, cf. the
  AN_NOT masking).
- **Cross:** per-backend emission; 32-bit pairs need carry-chain checks.
  Land x86-64 first behind the flag ({$Q-} default = zero codegen change,
  self-host unaffected), cross incrementally.

## Acceptance

- tint642.pp passes fully and leaves pxx.skip (testreqword's add/sub/mul/succ
  wrap paths all raise; {$Q-} sections still wrap).
- tint643.pp: `on eintoverflow do` (no var name) parses; overflow detection
  sections pass; entry leaves pxx.skip.
- New test: {$Q+} add/sub/mul overflow raises catchable EIntOverflow; {$Q-}
  wraps; subword (byte/word) widths check correctly.
- Conformance sweep stays 293+/0.

## Log
- 2026-07-15 — resolved, commit 17562666.
