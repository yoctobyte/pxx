---
prio: 40
track: N
type: bug
blocked-by: []
---

# `%-*s` — dynamic width from an argument — was unsupported

- **Type:** bug (NilPy, loud) — **Track N**
- **Found:** 2026-08-09, writing a table-formatting program and diffing it
  against CPython.
- **Status:** FIXED the same session.

```python
W = 8
print("%-*s|" % (W, "ab"))    # CPython "ab      |"
                              # pxx     ValueError: unsupported format character "*"
```

`%*s` and `%.*f` failed the same way.

## Why it matters more than "one format flag"

`*` is what a report uses when the column width is COMPUTED rather than literal
(`W = max(len(r) for r in rows)`), so the entire idiom was unavailable — and the
failure is at run time, inside the formatting call, not at the point the width
was decided.

## Fix

`pypercent_format` reads the width (and, after `.`, the precision) from the
argument list when it sees `*`, consuming it BEFORE the value. That ordering is
the part an implementation gets wrong: `"%s=%*d" % ("k", 4, 7)` must read `"k"`,
then `4` as the width, then `7` as the value — asserted.

Two CPython rules that are not obvious, both pinned:

- a **negative** starred width means left-align with the magnitude as the width
  (`%*s` with −8 equals `%-8s`);
- a **negative** starred precision is treated as absent.

## Verified
`test/test_nilpy_percent_star_width.{npy,expected}` (`.expected` from CPython):
starred width left/right/negative/zero, starred precision, both at once
(`%*.*f`), the mixed ordering case, and the plain forms as controls — `*` shares
the width slot with the digit parse, so a fix that captured too much would break
every ordinary `%-8s`. `gate.sh quick` GREEN.
