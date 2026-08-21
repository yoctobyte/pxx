---
track: A
prio: 40
type: refactor
blocked-by: []
summary: "`(TargetArch <> TARGET_XTENSA) and ((TargetArch <> TARGET_RISCV32) or (not EspBareBoot))` appears verbatim NINETEEN times in parser.inc, always answering one question: does this target link the builtin RTL unit at all? Give it a name. The duplication is the mechanism by which the next ESP-adjacent target gets it wrong in some of the nineteen and right in the rest."
status: done
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

---

## Resolution (2026-08-21)

Done in two passes, and the second pass is the interesting half.

**Pass 1** (`a0c60062a`, earlier this session, landed while scoping the riscv64
ticket): `TargetIsEspClass` in `compiler/util.inc`, 21 call sites replaced — 20 in
`pasparser_prog.inc`, 1 in `pasparser_proc.inc`. Nineteen was an undercount by the
time it was measured.

**Pass 2** (this commit): the ticket's own instruction — *"check the other
spellings while there ... the point is to look, not to assume"* — turned up **three
more** verbatim copies that pass 1's grep had not covered, because they are not in
the parser pre-scan at all:

| site | what it guards |
| --- | --- |
| `cparser.inc` | the C program's default-RTL pull (`__pxx_write`/`__pxx_read`, builtinheap, pxxcio) |
| `pasparser_proc.inc` | the same pull reached from a **unit** rather than a program |
| `compiler.pas` | appending the PAL backend dir to the default `-Fu` search path |

Each already carried a comment saying, in prose, *"same guard as the Pascal
default-RTL pull"* / *"guarded like the Pascal default-RTL pull"*. So the sameness
was **documented and not encoded** — three authors independently noticed the
identity, wrote it down in a comment, and copied the expression anyway. That is a
sharper version of the ticket's own argument than the twenty in the pre-scan:
those at least look like one block you would edit together, whereas these sit in
three different files, one of them a different frontend.

Total: **24**, not 19.

### The name

Ticket suggested `TargetLinksBuiltinUnit`; landed as `TargetIsEspClass` (negated at
each site) for two reasons. It states the *condition* rather than one *consequence*
— `compiler.pas`'s use is about a `-Fu` search path, which does not link anything,
so the consequence-name would have read as a lie there. And the negation is the
form every site already wanted (`not TargetIsEspClass`), where a positive
`TargetLinksBuiltinUnit` would have inverted the polarity of all 24 conditions and
made the diff unreviewable against the originals.

### Deliberately left alone

- The **13 sites** spelling `(TargetArch = TARGET_XTENSA) or (TargetArch =
  TARGET_RISCV32)` with **no profile test** (`emit.inc`, `elfwriter.inc`,
  `exception_emit.inc`, `pasparser_decl.inc`, `lexer.inc`, `pasparser_prog.inc`).
  They look like one concept and are several — "no DWARF", "the only two
  `--emit-obj` targets", "`Real` is `Single`", "no hardware FPU". Collapsing them
  would assert a sameness that is not there, which is the same mistake as the
  duplication, pointing the other way. Recorded in the function's own comment,
  because that is where the next person will look.
- `(TargetArch = TARGET_RISCV32) and (not EspBareBoot)` in `cparser.inc` and
  `pasparser_prog.inc` — reads similar, asks the opposite and narrower question
  ("is this *hosted* riscv32", for the softfloat pull). Not this predicate.

### Gate

`make compiler/pascal26` converged in 1 round, **byte-identical** — which is the
whole proof the ticket asked for: a pure renaming of a condition cannot move the
fixedpoint, and the compiler is the largest Pascal program available to exercise
the twenty-two Pascal-side sites. Plus, since the fixedpoint says nothing about
the C site or the ESP sites, all four affected paths built and ran directly: C
native (`printf` through crtl), Pascal native, hosted riscv32 under qemu, and both
bare-metal profiles (riscv32 `--esp-profile=bare`, xtensa) building clean.
`gate.sh quick` GREEN.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
