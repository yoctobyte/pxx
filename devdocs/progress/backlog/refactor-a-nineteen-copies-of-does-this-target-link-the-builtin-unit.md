---
track: A
prio: 40
type: refactor
blocked-by: []
summary: "`(TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot))` appears verbatim NINETEEN times in parser.inc, always answering one question: does this target link the builtin RTL unit at all? Give it a name. The duplication is the mechanism by which the next ESP-adjacent target gets it wrong in some of the nineteen and right in the rest."
---

# Nineteen copies of "does this target link the builtin unit?"

## The finding

    (TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot))

Nineteen verbatim occurrences in `parser.inc`, all in the pre-scan that decides
whether a program pulls `builtinheap` / the builtin conversions — one per construct
that would need them (`Str`/`Val`, Variant, `is`, variable field widths, and so on).

It is one question — *does this target link the builtin RTL unit at all?* — written
out nineteen times instead of named once. The condition is not obvious on sight
either: the xtensa half is unconditional, the riscv32 half applies only under
`--esp-profile=bare`, and the asymmetry is load-bearing.

## Why it is worth fixing

Not for the line count. **Nineteen copies is how the twentieth construct gets it
wrong, and how the next bare-metal target gets added to some of them and not
others** — a silent, per-construct partial rollout, which
`devdocs/dev/normalise-dont-special-case.md` names as the shape whose second arm
stays broken. The failure mode is not a crash: it is `StrInt not loaded` at link
time for one construct and not its sibling, far from the omission.

There is already precedent for the fix in this exact area — `EmitIoLockStubsForTarget`
and (as of `91ca417b3`) `EmitSignalRuntimeForTarget` are the same move applied to
per-arch emission choices.

## Shape of the fix

A named predicate near the pre-scan — `TargetLinksBuiltinUnit` reads best — and
nineteen call-site replacements. Then the ESP rule is stated once, with the reason
(no OS, no RTL to link against under `--esp-profile=bare`), and adding a target is a
one-line edit.

**Gate: the output must be byte-identical.** This is a pure renaming of a condition;
if the self-host fixedpoint moves, the predicate is not exact. That makes it an
unusually safe refactor to verify — the gate proves the whole thing.

Check the other spellings while there: `EspBareBoot` is also tested alone in
`emit.inc`, `exception_emit.inc`, `lexer.inc` (twice), `elfwriter.inc` (twice) and
`ir_codegen.inc`. Some of those are genuinely a different question (an ELF layout
decision is not "do we link the RTL"); the point is to look, not to assume, per
`devdocs/dev/normalise-dont-special-case.md`'s grep-for-the-sibling rule.

## Provenance

Found 2026-08-19 by frank3 surveying riscv32/xtensa coupling for the omission
defines ([[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]).
**Not a blocker for that ticket** — these are `TargetArch` comparisons, not
references to backend symbols, so they compile fine with a backend omitted. Filed
separately because it is a better find than the thing being looked for.
