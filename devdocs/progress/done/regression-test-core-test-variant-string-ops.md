---
prio: 70
track: A
status: done
owner: claude-A
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_variant_string_ops.pas red at df21e490d798 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-23T22:20:48Z
- **Test source:** test/test_variant_string_ops.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_variant_string_ops.pas'` at df21e490d7989a812fc35b0f5f2dc5b5ea0e4bab

## Range
bad `df21e490d798`, last good `fd93e4a71c37`, 13 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1397860/test_variant_string_ops26  [code=129332B  data=3248B  bss=42700B  procs=229]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triaged and closed 2026-08-24 (claude-A) — the TEST was wrong, not the compiler

Reproduced at HEAD: the program dies with
`Runtime error: EVariantError, cannot convert string to a number` at section 4,
which asserts

```pascal
v1 := 'abc'; v2 := 123;
writeln(v1 = v2);    { expected FALSE }
writeln(v1 <> v2);   { expected TRUE  }
writeln(v1 < v2);    { expected FALSE }
writeln(v1 > v2);    { expected FALSE }
```

Bisect range: the culprit is `46b7aa284`,
[[bug-a-a-variant-comparison-does-not-coerce-a-stringy-operand]], which made a
comparison with exactly one stringy operand convert the text and compare
numerically — FPC's rule, and the one the ticket was filed to get.

**Checked against the oracle before touching anything**, which is the whole
point: `fpc 3.2.2 -Mobjfpc -O1` on the same four rows does not print
FALSE/TRUE/FALSE/FALSE. It **raises `EVariantError: Invalid variant type cast`**
on the first one. `'abc'` is not a number, so the conversion fails, and FPC
lets that failure out.

So the expectation this test locked in was pxx's OLD rule — "a side whose tag is
neither string nor char compares unequal, unordered" — and that rule was the
defect. The compiler now agrees with FPC on both halves: `'123' = 123` is True,
`'abc' = 123` raises.

### What changed

- `test/test_variant_string_ops.pas` section 4 now asserts the rows both
  implementations agree on (`'123'` vs `123`, `'99' < 123`), with the reason and
  the pointer to the raising case written into the file. The Makefile's inline
  expected stream moves with it: the last four lines become
  `TRUE FALSE TRUE FALSE`.
- The RAISING case gained real coverage rather than being dropped:
  `test/test_variant_comparison_coerces_a_stringy_operand.pas` — which already
  carries `sysutils` and a `try/except`, unlike the deliberately unit-free test
  above — now asserts that `v('abc') = v(123)` raises, plus three rows proving
  it is the CONVERSION that raises and not the mixed tags.

Green on x86-64, i386, aarch64 and arm32, and `ALL OK` under fpc 3.2.2.

### Note for the next auto-filed regression

The stub's `track: P` guess was wrong — a Variant comparison rule is Track A
(shared runtime + `EmitVarBinOp`), not the Pascal frontend. Harmless here
because the same agent held both, but the guess is made from the test's file
name and will keep landing Variant and RTL regressions in P.
- 2026-08-24 — resolved, commit f5dfab2b5.
