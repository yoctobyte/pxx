---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`2.0 ** 10000` answers +inf where CPython raises OverflowError, and so does `1e300 * 1e300`. A program that catches OverflowError — the documented way to detect this in Python — silently gets an infinity instead and carries on."
status: working
owner: claude-acpn
---

# Float overflow answers `inf` where CPython raises `OverflowError`

Measured 2026-08-16 while working
[[bug-a-nilpy-star-star-has-its-own-low-precision-pow]]; pre-existing on the
pinned binary and on HEAD alike, and unrelated to that ticket's plumbing.

## Repro

```python
print(repr(2.0 ** 10000))   # CPython: OverflowError   NilPy: inf
print(repr(1e300 * 1e300))  # CPython: OverflowError   NilPy: inf
```

## Why it is a bug and not laxity

NilPy accepting what CPython REJECTS is a feature, not a defect — but this is
the other direction in disguise. Code that WORKS on CPython is code like

```python
try:
    scale = base ** exponent
except OverflowError:
    scale = FALLBACK
```

which is the documented way to detect this, and on NilPy the `except` never
runs and `scale` becomes `inf`. The wrong branch is taken silently, which is the
test in `devdocs/dev/nilpy-semantics-divergences.md` for "a program CPython
accepts and runs can observe it".

## Scope

Not pow-specific: the multiply does it too, so this is the general float
overflow policy rather than one operation. IEEE says +inf; CPython's float
arithmetic raises for `**` and for the C-level operations it wraps. Deciding
which of those NilPy follows — and whether it is worth a per-operation check on
every float multiply — is a design call, so it may want a `decide-` ticket
before any code.

Note that pxx's own Pascal side must keep IEEE semantics; whatever lands has to
be gated on `PyNodeIsUser`, not on `PyProgramMode`
(project_pyprogrammode_is_program_wide_not_user_code).
