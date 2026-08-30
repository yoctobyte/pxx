---
track: P
prio: 70
type: regression
blocked-by: [bug-n-tkinter-is-missing-from-the-python-serving-unit-list]
summary: "TRIAGED. Not a broken build: the cause is e1109d7bc (a bare NilPy import resolves to Python), and 4e27dc2be1 named in the header is docs-only. Two halves. Six test/** fixtures importing Pascal units were rewritten to the quoted spelling and now pass their exact Makefile assertions. The six examples/tk/*.npy are NOT a test bug -- lib/pcl/tkinter.pas is a deliberate Python-module facade missing from the curated list; blocked on the Track A ticket that adds it."
status: done
owner: frankA
---

# regression CASCADE: 12 jobs newly red at 4e27dc2be114 (auto-filed by twatch)

- **Type:** regression cascade (auto-filed by Track T watcher, host plexus).
  Untriaged. 12 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-19T14:43:46Z
- **Root cause (triaged 2026-08-19, replaces the auto-filed guess):**
  `e1109d7bc feat(A,N): a bare NilPy import resolves to Python, not a Pascal
  unit`. The header sha `4e27dc2be1` is **docs-only** (three markdown files) and
  cannot break anything — the auto-file landed on the wrong end of an untested
  range `48a60d096..4e27dc2be1`, and `e1109d7bc` is earlier in it.
  The behaviour is INTENDED and is not to be weakened
  (`decide-nilpy-imports-that-collide-with-a-pascal-rtl-unit`, user 2026-08-19).

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier native --job '<job>'` at 4e27dc2be11471f92064756e17d426617d0d284b

## Newly red jobs
- `test-core#src:examples/tk/callbacks.npy`
- `test-core#src:examples/tk/facade_and_paths.npy`
- `test-core#src:examples/tk/field_class_identity.npy`
- `test-core#src:examples/tk/import_in_body.npy`
- `test-core#src:examples/tk/shadow_format_except.npy`
- `test-core#src:examples/tk/tkinter_facade.npy`
- `test-core#src:test/test_nilpy_array_of_const_unit.npy`
- `test-core#src:test/test_nilpy_class_named_after_its_imported_base.npy`
- `test-core#src:test/test_nilpy_multiple_inheritance_imported_base.npy`
- `test-core#src:test/test_nilpy_qualifier_vs_cproc.npy`
- `test-core#src:test/test_nilpy_renamed_class_attrs.npy`
- `test-core#src:test/test_nilpy_subclass_unit_base.npy`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*


## Triage — 2026-08-19, against a self-host fixedpoint at `5b1539fc7`

Each of the 12 was reproduced and rewritten *individually*, not sed-ed as a set.
They are two different problems that shared one error message.

### Half 1 — test fixtures importing Pascal units. FIXED here.

`test/nilpy_units/{fmtprobe,samenamebase,mixinproto,mixinproto2,cprobe_unit,basehook}.pas`
are Pascal units, and these `.npy` files imported them by bare name. That is
exactly the spelling the new rule closes, and the compiler names the replacement
in its own diagnostic. Rewritten to `import '<name>.pas' as <name>`, each with a
comment saying why:

| file | verified |
| --- | --- |
| `test_nilpy_array_of_const_unit.npy` | `x:2` |
| `test_nilpy_class_named_after_its_imported_base.npy` | `override: derived / inherited: pascal-side / base: base pascal-side` |
| `test_nilpy_multiple_inheritance_imported_base.npy` | all four lines |
| `test_nilpy_qualifier_vs_cproc.npy` | `main / bye` |
| `test_nilpy_subclass_unit_base.npy` | `override: KeepCase / inherited: keepcase` |
| `test_nilpy_two_imported_bases_fail.npy` | reaches its own wall (below) |

Verified by running each one's **exact Makefile assertion** — the recipe's
`printf` comparison and `-Futest/nilpy_units` flag, not just the compile. All
seven PASS (`renamed_class_attrs` included, see below).

**The negative test was the one that needed care.**
`test_nilpy_two_imported_bases_fail.npy` asserts that two imported bases are
REFUSED. It was still "failing to compile", so the `!` in front of it was
satisfied — but for the wrong reason: it now died at the import wall, and the
paired `grep -q 'names TWO base classes whose bodies are not in this file'`
caught it. That grep is the only thing standing between this shape and a test
that passes while asserting nothing. After the rewrite it reaches the real
refusal at line 18 and the grep matches.

**The shape to check for, generally.** A negative test whose only assertion is a
leading `!` asserts *"something went wrong"*, not *"the right thing went wrong"* —
so any rule change upstream of it can move the failure to a new wall and the test
stays green while asserting nothing. Whenever a refusal test sits downstream of a
changed rule, check that it still dies at ITS OWN message; the paired `grep -q` is
what makes that checkable, and a `_fail`/`_reject` test without one cannot be
checked at all. Third instance of this family on 2026-08-19.

**Two jobs in the red set needed no edit at all** and were failing as
recipe-block collateral:
- `test_nilpy_renamed_class_attrs.npy` — imports `renclsmod`, which is a `.py`,
  so the new rule never touched it. Its job failed on the *second* assertion in
  its block, the two-imported-bases negative test above.
- `test_nilpy_kwargs_by_name.npy` — has no imports whatsoever; it shares a
  recipe block with `examples/tk/callbacks.npy` and dies when that aborts.

**`lib/rtl/configparser.pas` needs no edit** (raised as a possible Track B
question): `configparser` is already in the curated `PyRtlUnitServesPython`
list, so it still resolves by bare name. It was only a downstream source in a
job line.

### Half 2 — the six `examples/tk/*.npy`. NOT a test bug; blocked.

These are not fixtures that happen to import a Pascal unit. `lib/pcl/tkinter.pas`
was written to BE Python's `tkinter`, and says so in its own header — the missing
entry in the curated list is the defect. Rewriting the examples would put the
spelling every real tkinter program uses out of NilPy's reach. Filed as
`bug-n-tkinter-is-missing-from-the-python-serving-unit-list` (Track A,
`compiler/parser.inc`) with the one-line fix **measured**: with `tkinter` added
to the list, all six compile and no example or test needs an edit.

Not applied here — it is a shared `parser.inc` edit and the A/P slot is held.

### One thing lost, and it is a Track U question

There is no spelling for a from-import of a Pascal unit: `from 'basehook.pas'
import ConfigBase` is refused with *expected a module name after from*. So
`test_nilpy_subclass_unit_base.npy` lost one of its three assertions; the other
two (dotted base, unqualified base) still hold and its header records what went
and why. Whether the quoted form should be accepted after `from` is noted in the
Track A ticket.


---

**Unblocked and moved to `backlog/` by the coordinator, 2026-08-28.** Its declared
`blocked-by` names a ticket that has since been resolved, so this was sitting in `blocked/` —
which `ready`/`next` never scan — while it was actually rankable. Nothing about the work
changed; only the record was stale. Found by a sweep (see
`chore-t-nothing-re-checks-a-blocked-by-edge-after-its-blocker-closes`); 14 tickets repo-wide
carry at least one `blocked-by` naming a closed ticket, five of them fully unblocked.

---

## RESOLVED, 2026-08-30 (frankA) — verification only, no code change

All 12 jobs of the cascade are green, plus the two that were failing as
recipe-block collateral. **Nothing needed fixing**: half 1 was fixed in the
2026-08-19 triage, and half 2's blocker
(`bug-n-tkinter-is-missing-from-the-python-serving-unit-list`) has since been
resolved — `tkinter` is in `PyRtlUnitServesPython`
(`compiler/pasparser_proc.inc:2847`, which is where `parser.inc`'s copy went in
the P/A split). The ticket was open only because nothing re-checked it after the
blocker closed.

Verified against a self-host fixedpoint at `22c67e5ea61e`, by running each job's
**exact Makefile assertion** — the `-Futest/nilpy_units` flag and the
`expect_same.sh` comparison — not merely the compile.

| job | verdict |
| --- | --- |
| `examples/tk/tkinter_facade.npy` | compiles (compile-only per recipe: needs an X display) |
| `examples/tk/field_class_identity.npy` | compiles (compile-only) |
| `examples/tk/callbacks.npy` | compiles (compile-only) |
| `examples/tk/import_in_body.npy` | `in a suite left / before / after both` |
| `examples/tk/shadow_format_except.npy` | `module function / Tap BPM: 92.5 / caught: clipboard` |
| `examples/tk/facade_and_paths.npy` | all six lines |
| `test_nilpy_array_of_const_unit.npy` | `x:2` |
| `test_nilpy_class_named_after_its_imported_base.npy` | all three lines |
| `test_nilpy_multiple_inheritance_imported_base.npy` | all four lines |
| `test_nilpy_qualifier_vs_cproc.npy` | `main / bye` |
| `test_nilpy_renamed_class_attrs.npy` | all six lines |
| `test_nilpy_subclass_unit_base.npy` | `override: KeepCase / inherited: keepcase` |
| `test_nilpy_two_imported_bases_fail.npy` (collateral) | refused, **and at its own message** |
| `test_nilpy_kwargs_by_name.npy` (collateral) | all four lines |

**The negative test was checked the way this ticket's own triage said to check
it.** `two_imported_bases_fail` is satisfied by any failure, so `!` alone would
pass on a compiler that died at the import wall instead of the real refusal. Its
paired `grep -q 'names TWO base classes whose bodies are not in this file'`
matches, so it still dies at ITS OWN wall.

Three "output mismatches" appeared in the first sweep and were **my harness, not
the tests**: I extracted `TESTTMP` from the Makefile without expanding its
`$(shell ...)` calls, so the binaries were written to a literal path and the
runs produced a bash error. Re-run with a real directory, all three pass.
Recording it because a mismatch on a *just-unblocked* ticket is exactly the
shape one would be tempted to file.

### The one lost assertion is tracked, not dangling

The triage flagged that `from 'basehook.pas' import ConfigBase` has no spelling
(`expected a module name after from`), costing
`test_nilpy_subclass_unit_base.npy` one of its three assertions. Still true at
this binary — and it was escalated properly rather than guessed: answered in
`decided/decide-should-from-accept-a-quoted-foreign-file`, and carried by
`feature-n-from-accepts-a-quoted-foreign-file` [N p45] and
`feature-n-a-quoted-from-import-reaches-another-language`. The assertion comes
back with that feature, not with this ticket; the test's header already records
what went and why.

`blocked-by:` still names the closed blocker — left as the historical record of
why this sat in `blocked/`; the coordinator's 2026-08-28 note above is the live
statement.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
