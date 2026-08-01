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
