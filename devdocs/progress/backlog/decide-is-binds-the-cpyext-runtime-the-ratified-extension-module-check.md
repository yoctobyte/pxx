---
track: U
prio: 30
type: decision
blocked-by: []
summary: "decide-nilpy-import-rule-vs-a-cpyext-extension-module ratified `PyInit_<name>` as the extension-module criterion; the implementation substituted 'the unit binds the cpyext runtime' after measuring that PyInit_<name> holds for only 3 of the 6 real units, and flagged the deviation for the owner to overrule. Nobody overruled it either way, and it is now shipped, pinned in v391, and — as of this ticket — documented on the public website. Ratify the substitution or order it changed."
---

> **COST: one word.** Re-priced 2026-08-30 by frankD during the Track U triage.
> This is a **ratification**, not an open design fork. The measurement that
> killed the decided criterion is sound and reproducible, the substitute has
> shipped, is pinned in v391, and is documented on the public website; option 2
> would mean changing the evidence to fit the predicate, and nothing measured
> suggests option 3. **"Ratified" closes it and the code does not move.**
>
> It stays in Track U rather than being re-filed into a lane because no agent
> may ratify a deviation from an owner decision on its own — but it should be
> read as a paperwork item that has been mis-shelved among real decisions since
> it was filed, which is why it has sat at p30.


# Is "binds the cpyext runtime" the ratified extension-module check, or still awaiting overrule?

- **Track U** — a decision, not work. No files.
- **Raised by** frankD (Track D) while writing
  [[docs-d-name-resolution-pages-state-the-import-rule-with-no-cpyext-carve-out]].

## The fork

[[decide-nilpy-import-rule-vs-a-cpyext-extension-module]] decided the criterion in its
part 4: **`PyInit_<name>`**, in preferred shape (b) — the unit DECLARES itself and
`PyInit_<name>` VERIFIES the claim.

[[feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit]] kept shape
(b) and kept the declaration, but **substituted the verifier**, having measured that the
decided one is false:

| unit | `PyInit_` in its `uses`-clause C | is it `PyInit_<name>`? |
| --- | --- | --- |
| `hello_ext`, `argerr_ext`, `container_ext` | matching | yes |
| `cyadd_ext` | `PyInit_cyadd` | no — the **vendored** module's name |
| `markupsafe_ext` | `PyInit__speedups` | no — same |
| `fmt_ext` | none | no — a C-API **consumer**, not a module |

3 of 6. The two vendored cases are the *normal* case for a genuinely vendored
extension, not a corpus quirk. What shipped instead
(`PyUnitDeclaresExtensionModule`, `compiler/pasparser_proc.inc:3035`) is a lone
`{$PYEXTENSION}` line plus `pyruntime.c` present in the unit source.

The resolving agent wrote: *"This deviates from the decided criterion and is flagged
for the owner to overrule."* That flag sits in a `done/` ticket, which is a session
record nobody re-reads, so it has had no reader in nine days.

## Why it is worth one line of your attention now

It is no longer only an internal detail. It is pinned in **v391**, and this ticket's
sibling has just published the substituted criterion to `docs/**` — i.e. to the
website, as the documented contract for how a unit declares itself an extension
module. If the criterion is going to move, moving it before it is public costs
nothing and moving it after costs a docs correction plus anyone who wrote to it.

## Options

1. **Ratify the substitution** (recommended). The measurement that killed
   `PyInit_<name>` is sound and reproducible, the substitute holds for all six real
   units and for none of the 20 ordinary `.pas` files in `test/nilpy_units/`, and the
   negative test (`test_nilpy_pyextension_declaration_required`) pins the carve-out to
   the declaration rather than to what the unit links. Cost: amend the decided ticket
   so the record says what the code does. Docs already match.
2. **Order `PyInit_<name>` restored.** Requires fabricating a stub `PyInit_fmt_ext`
   and re-pointing the two vendored units' shims — i.e. changing the evidence to fit
   the predicate, which is the failure `_ext` was rejected for. Costs a docs
   correction.
3. **A third verifier.** Nothing measured suggests one, but the owner may want the
   declaration to stand alone with no check at all — simpler, at the cost of the
   anti-widening guard the negative test exists to hold.

**Recommendation: option 1**, and treat this ticket as the ratification record rather
than a re-litigation. The substance was decided; only the paperwork is open.
