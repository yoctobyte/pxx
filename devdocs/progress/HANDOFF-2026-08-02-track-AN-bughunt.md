Continue the A+N all-night bughunt on pxx (`/home/rene/frankonpiler`, master).
Standing goal: don't stop, don't ask questions, let Track T handle the matrix,
fix bug tickets, file new bugs you find and fix them.

## FIRST: uncommitted work in flight

Verified byte-identical to CPython, but **not gated and not pushed**:

- `compiler/builtin/pylib.pas` — the `,` thousands-separator format spec, in
  BOTH the int and float overloads; the two unsupported-spec sites now
  `raise ValueError` instead of `Halt(1)` (they aborted the process, so
  `try/except` round a format could not run); and a float spec naming no type
  and no precision now uses Python's general form —
  `"{:,}".format(1234.5)` is `1,234.5`, was `1,234.500000`.
- `test/test_nilpy_format_thousands.npy` (new) and its Makefile assertion —
  both written, assertion passes.

To finish: run **`make test-nilpy`** (this touched SHARED formatting, so the
full suite is warranted here rather than just quick), then commit and push, and
mark item 2 done on
`bug-nilpy-sweep-gaps-pow-thousands-sep-stepped-slice`.

## The loop

`make compiler/pascal26` (~12s — it IS the byte-identical self-host fixedpoint)
→ run your repro → `tools/testmgr.py --tier quick` → `make bootstrap` → push.

`make bootstrap` is the FPC seed build and is **mandatory whenever you add a
call that crosses an `.inc` boundary** — PXX is lax about declaration order and
FPC is strict, and neither `make` nor `gate.sh` runs FPC. That bit me once
tonight. Never run `gate.sh` in the dev loop; it is the pin gate.

## Test expectations

Generate with `python3 tools/mkesc.py <binary> <tmpname>` and verify with
`make -n test-nilpy | grep <tmpname> | bash -e`. Never hand-escape and never
re-derive the escaping in Python — three separate escaping bugs came from that,
each with a different cause (`%%`, unescaped `'`, unescaped `\`).

## Finding new bugs

`python3 tools/pydiff.py run <file>.py` diffs against CPython; it produced most
of tonight's finds. Surfaces already measured CLEAN, don't re-plough: strings
and formatting, container mutation, integer arithmetic, exceptions, inheritance
dispatch, iteration and flat unpacking.

When guessing at a trigger fails twice, switch to mechanical delta-debugging —
reduce line-by-line under a predicate that keeps the construct of interest AND
requires the candidate to still be valid Python, so like is compared with like.
Without that second condition the reduction collapses to something that fails
for an unrelated reason.

## Top of the queue — both prio 80, both need a decision before code

- `bug-nilpy-identifiers-are-case-insensitive` — `x = 1; X = 2` gives `2 2`.
  The resolver is shared and case-insensitivity is CORRECT for Pascal (FPC
  parity). Needs a per-frontend split, staged, with both suites in the gate.
- `bug-nilpy-function-local-assignment-clobbers-module-global` — and `global x`
  currently works ONLY because the leak exists, so both halves must land
  together.

## Hard-won, read before re-attempting anything

Three fixes were **reverted** tonight because the obvious half turned a loud,
correct refusal into a silent wrong value or a crash: the `*rest` arity relax,
the class-attribute lookup fallback, and a case-sensitivity flip. Each ticket
records the counter-example. If a ticket says an approach was tried and
rejected, believe it.
