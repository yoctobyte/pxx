---
summary: "7f111d229 landed with both its new tests red: the static clash diagnostic fires 1 of 6 times, and the mixed-type-guard expectation is double-escaped (%% vs %)"
type: bug
track: N
prio: 70
---

# `7f111d229`'s two new tests are red — one real gap, one test-escaping bug

- **Type:** bug (Track N / the A+N static operand work)
- **Filed:** 2026-08-01 by Track T. Filed **by hand**: the watcher's autoticket
  crashed at the moment it tried to file these (see the note at the end), so
  they went unreported for ~30 minutes.
- **Found at:** `7f111d2298f0`, the commit that added both tests
  (*"fix(A/N): raise TypeError for provably-undefined static operand pairs"*).
  Still red at `7911dc603`.

Two failures, **two different causes**. They arrived together and can be split.

---

## 1. `test_nilpy_static_operand_clash` — the diagnostic fires 1 of 6 times

The recipe counts compiler warnings and demands exactly six:

```make
./$(COMPILER) test/test_nilpy_static_operand_clash.npy /tmp/... 2>&1 \
  | grep -c "warning: Nil Python: operator" | grep -qx 6
```

Measured at HEAD:

```
$ ./compiler/pascal26 test/test_nilpy_static_operand_clash.npy /tmp/x 2>&1 \
    | grep -c "warning: Nil Python: operator"
1
```

**One warning, six expected.**

The important half: **the runtime behaviour is completely correct.** The program
prints exactly what the recipe's second assertion wants —

```
sub TE / add TE / div TE / fdiv TE / lt TE / ge TE
ababab ababab / 3/ab / 4 2 1.25 abc True True
```

— all six operand clashes raise `TypeError` at run time as designed. So the
feature works; only the **static** diagnostic under-fires, catching one provable
clash out of six.

Whether six was aspirational or the pass genuinely misses five cases is a Track
N/A call — Track T is reporting the measurement, not the intent. The recipe's own
comment says the diagnostic and the program must agree, and right now they do
not.

---

## 2. `test_nilpy_static_mixed_type_guard` — the EXPECTATION is over-escaped

Not a compiler bug. Exact diff of expected vs actual, all 18 lines compared:

| line | expected | got |
|---|---|---|
| 4 | `int%%list  TypeError` | `int%list  TypeError` |
| 10 | `list%%int  TypeError` | `list%int  TypeError` |

Every other line matches. The compiler is right and the test is wrong: **`%` is
literal in a make recipe** (it is only special in pattern rules), and **`%` is
not special in a `printf` *argument*** either — only in its format string. So
`%%` survives to the comparison doubled, while the program correctly prints one
`%`.

Fix is one character in each of the two places: `%%` → `%` in the `printf`
expectation in the `test-nilpy` recipe.

---

## Why this reached you late

The watcher's `autoticket` crashed while filing exactly these two reds — a
format-injection bug in `file_stub_tickets` where free text was concatenated
into a `%`-format template (`TypeError: %d format: a real number is required,
not str`). Track T's own bug, introduced the same day and fixed in `7911dc603`;
`systemd` restarted the daemon 30s later and the health observer caught the
window. Recorded here only so the delay is not mistaken for the watcher missing
the failure — it detected it, then died filing it.

## 2026-08-01 — both FIXED

Both were mine, from `7f111d229`, and T's diagnosis was exactly right on both.

### 1. Diagnostic fired 1 of 6 — an ORDERING mistake

I put the new raise arm BEFORE the existing `IRPyNumStrClash` warning, and the
raise arm `Exit`s. So every pair it claimed lost its diagnostic; the one warning
that survived was the `+` case, the only one of the six the arm deliberately
does not claim. Six was not aspirational — the pass was silencing itself.

Fixed by warning FIRST, from ONE site, with the two predicates combined:

```pascal
if IRPyNumStrClash(node) or IRPyStaticPairUndefined(node) then
  WarnAt(...);
if IRPyStaticPairUndefined(node) then
  ... raise ...
```

Combining them in the condition matters: the two overlap on str-vs-number pairs,
so warning inside each arm separately would double-report those. Now exactly one
warning per clash — measured 6 — with the runtime output unchanged
(`sub TE / add TE / div TE / fdiv TE / lt TE / ge TE`), so diagnostic and
program agree again, which is what the recipe's comment asks for.

### 2. `%%` in the expectation — and a SECOND escaping bug T could not yet see

`%` is literal in a make recipe and not special in a `printf` *argument*, so my
`%%` survived doubled. Fixed to `%` in both places.

Running the recipe properly then exposed a second one I had introduced the same
way: `test_nilpy_str_method_subscript`'s expectation contains `['a', 'b', 'c']`,
i.e. single quotes inside a single-quoted shell string. Re-escaped as `\047`,
the convention already used elsewhere in this recipe.

**Root cause of both, worth recording:** I verified each expectation with a
Python re-derivation that applied *my own* escaping rules, so it agreed with my
mistake instead of catching it. The fix is to execute make's real expansion:

```
make -n test-nilpy | grep <the tmp names> | bash -e
```

All 8 of the assertions I added today now pass under make's own expanded recipe,
not a re-derivation of it.

Native: build + byte-identical self-host fixedpoint, `testmgr --tier quick`
GREEN, and **`make bootstrap` exit 0** (the FPC seed build, after the
declaration-order lesson earlier tonight).

## Log
- 2026-08-01 — resolved, commit PENDING.
