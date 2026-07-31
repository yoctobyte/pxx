---
track: N
prio: 40
type: feature
---

# `str.format` with more than one argument

`"{:.1f}".format(x)` works. `"{} and {}".format("a", 2)` does not: the
two-argument pylib overload is written and the call SEGFAULTS — the second
Variant does not arrive correctly through the str-method call path, while the
identical one-argument call is fine.

Refused at the call site with a diagnostic rather than shipped, because a crash
is worse than a "not implemented".

## FIXED (this session)

Root cause, found by comparing against `.rjust(w, fill)` as suggested: the
generic argument-collection loop was never the problem — every multi-arity
str method already works through it. The bug was that `FindProc(pname)`
(pyparser.inc) looks a proc up by bare NAME, not arity-aware, so a
same-named `pystr_format` overload pair (1-arg and 2-arg) resolved to
whichever was registered FIRST regardless of how many arguments were
actually parsed — the second Variant then arrived through the 1-param
overload's ABI and the call segfaulted. `.rjust` and every other
multi-arity str method already sidestep this by using a DIFFERENT,
arity-suffixed proc NAME per arity (`_from`, `_c`, `_n`) rather than
relying on overload resolution through `FindProc`; `format` just hadn't
gotten the same treatment.

Fix: added `pystr_format2` (a separate proc, not a second `pystr_format`
overload) calling the ALREADY-two-arg-capable `PyFormatApply(fmt, a, b, 2)`
that was sitting unused — the pipeline underneath was already built for
this, only the entry point and the frontend's arity gate were missing. The
frontend's `-6` case now picks `pname + '2'` when two arguments were parsed.
Three-or-more placeholders remain a loud compile-time refusal (unchanged
scope — still needs `PyFormatApply` widened past a fixed 2-arg signature,
which is more machinery than this fix's segfault-elimination scope).

Named/index fields (`{name}`, `{0}`) remain unimplemented — unchanged, not
attempted here; the placeholder walk in pylib's `PyFormatApply` still
handles positional `{}` and `{:spec}` only.

## Log
- 2026-07-31 — resolved, commit bb7395a21.
