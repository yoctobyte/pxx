---
track: T
prio: 70
type: bug
blocked-by: []
summary: "72 `NOT verified` sites in the Makefile print an honest sentence and exit 0, so a box missing a qemu or a multilib gcc runs a NARROWER tier and reports an IDENTICAL verdict. testmgr.py classifies SKIPs and publishes `skip_holes` into the pin manifest, but a recipe's OWN `<target>: SKIP` line is deliberately excluded (tools/testmgr.py:2812-2824) — so none of the 72 is counted. MEASURED 2026-09-12 on borg: two `gcc -m32` oracles (Makefile:13986, 14147, 21430) had been silently not running; multilib was simply absent. The comment at :2812 already names this exact case as unsolved and RULES OUT the tempting fix (loosening the classifier match); it needs a CHANNEL from the recipe. Cited there too: the gtk undercount, five holes uncounted for seven weeks because an emitter said `host tool absent:` where the classifier looked for `tool absent:` — the same failure, and the undercount is always DOWNWARD. THIS ALSO MAKES `skip_holes == 0` UNSOUND AS THE -O3 PROMOTION PROOF GATE."
---

# A recipe that self-skips a missing oracle is not counted as a coverage hole

Measured by the Track T seat on borg, 2026-09-12, while fixing the 32-bit oracle
rows; scoped and counted by it, filed here because the fix spans two subsystems.

## What was measured

- `grep -c 'NOT verified' Makefile` = **72**. The shape is
  `if command -v $$q >/dev/null; then <run oracle>; else echo "... absent, ... NOT verified"; fi`
  — 26 distinct `command -v` guards plus the `gcc -m32` ones. **Every one prints
  its own honest sentence and exits 0.**
- `tools/testmgr.py:2819-2824` holds the SKIP classifier prefixes
  (`SKIP_CORPUS_ABSENT`, `SKIP_TOOL_ABSENT`, `SKIP_HOST_TOOL_ABSENT`,
  `SKIP_HOST_DEV_ABSENT`, `SKIP_HOST_CAP_ABSENT`) and counts those as holes.
- The comment at `:2812-2818` excludes a recipe's own `SKIP` **deliberately**, and
  states the open question in its own words: whether a recipe that self-skips for
  a coverage reason *"should be able to SAY so is a real question and a separate
  one; it needs a channel from the recipe, not a looser match here."*

**So the wrong fix is already ruled out by the code it would touch.** Do not
widen the classifier's match; give the recipe a way to declare the skip.

## Why this is a defect and not a style complaint

**A guard that cannot fail prints PASS.** These guards cannot fail: a box with no
`qemu-riscv32` runs fewer jobs and emits the same verdict as a box that ran them
and agreed. borg happens to have qemu-i386/arm/aarch64/riscv32, so those 26 were
passing through there — **the exposed box is the one nobody has looked at**, and
the verdict is the instrument that would have to tell you, which is the one thing
it cannot do.

**AND IT REACHES A GATE.** CLAUDE.md defines the `-O3` promotion PROOF grade as a
full run with `skip_holes == 0`. If up to 72 holes are structurally uncountable,
`skip_holes == 0` is satisfiable by a box that simply lacks tools — the flag can
come out true without the property holding, which is the same animal as a guard
that cannot fail. Whatever else is decided, **that connection should be recorded
before anyone promotes an optimisation level on that grade.**

The undercount has already bitten once and is cited in that same comment: the gtk
jobs, **five holes uncounted for seven weeks**, because the emitter said
`host tool absent:` and the classifier looked for `tool absent:`. Twice now, and
**silently, and always downward** — the direction that flatters the tier.

## The evidence that settles it, and it runs the OTHER way

Measured on borg the same day, full tier at `051b229aa`, after multilib landed:
**18 rows moved to pass, and 16 of the test-core ones WERE ALREADY PASSING** —
they had been green while silently not running their i386 oracle. `test-core#763
838 839 850 885 924 952 953 955 956 1065 1066 1076 1136 1137 1139 1151` plus
`test-emit-obj#02`, covering cfnptr/cfnsr, casmgnu386, c_uapilay_gcc32, pcdecl
and c_obj_data_dup.

**So the pass count barely moved and the coverage behind it changed completely.**
That is the worst available shape for this class: the verdict is not merely
unable to report the hole, it reports the same number before and after the hole
is closed. A tier diff — the instrument anyone would reach for — cannot see it
either. What improved is *what the greens mean*, and nothing in the run says so.

The same run reported `skips 0` and `coverage_holes 0`. On that day's evidence
those two zeros mean *"borg happens to have every qemu"*, not *"the tier verified
everything"* — and they would read identically on a box that had none.

## The shape of the fix

A channel from the recipe to the classifier: a recognised skip line a recipe emits
to mean *"I skipped and it IS a coverage hole"*, then route the 72 guards through
it so `skip_holes` counts them.

**Not taken on a peer's say-so.** This edits ~72 Makefile recipes plus a testmgr
channel, which is well past what the borg seat was handed; it asked for the owner's
word before picking it up, which is correct. Track T owns the tool, so the lane is
T's — the question for the owner is only whether it is worth the span now.

**Positive control, when it is built:** a box with a tool removed must report a
nonzero `skip_holes` for exactly the jobs that guard on it. A run where
`skip_holes` stays 0 after removing a qemu is the instrument failing, not a pass.
