---
slug: bug-p-a-compiler-tls-constant-is-not-a-constant-in-a-const-declaration
track: P
prio: 90
type: bug
status: done
created: 2026-11-26
found-by: pixx-cc (pixx's BSD menu entries): `pascal26 --os=netbsd compiler/compiler.pas` failed at 0778fedc93
tags: [pascal, const-eval, bsd, regression]
blocked-by: []
summary: "Every --os=netbsd, --os=openbsd and --os=dragonfly compile failed, even hello world, with `not a constant` in the ABI translator (`NB_TLS_SLOT_CTID = __pxxTlsFsEntrySlotOff div 8`, from 9b65baca4d). The compiler constants (__pxxTlsBlockSize, the TLS slot offsets, __pxxSigAltStackSize) folded in an expression but the const evaluator did not know them. One table now serves both (PasCompilerConstBuiltin). Test-core: test_compiler_constants_in_const_decls, compiled for every BSD."
---

# A compiler TLS constant was "not a constant" in a const declaration

9b65baca4d (2026-11-21) made the BSD ABI translators derive the ctid slot
from the slot map, `NB_TLS_SLOT_CTID = __pxxTlsFsEntrySlotOff div 8`, rather
than spell 14. The name folds to a literal in an EXPRESSION
(pasparser_expr.inc), but `ConstEvalFactor` had no arm for it, so the
declaration was "not a constant". The translators are compiled into every
program for their OS, so --os=netbsd, openbsd and dragonfly could not build
anything; FreeBSD's translator uses the name only in an expression and was
fine. No suite builds for those targets on Linux, so nothing noticed for
five days.

Fix: `PasCompilerConstBuiltin(name, v)`, the one table of these names and
values, read by the expression parser and by `ConstEvalFactor` (bare or with
`()`). Verified: `--os=netbsd|openbsd|dragonfly|freebsd compiler/compiler.pas`
all build.

Test: `test/test_compiler_constants_in_const_decls.pas` (each constant as a
const equals its expression form), and test-core compiles it for all four
BSDs.
