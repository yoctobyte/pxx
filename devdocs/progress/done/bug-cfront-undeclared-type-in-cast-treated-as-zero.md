---
track: C
prio: 65
type: bug
summary: "An undeclared TYPE NAME used in a cast is only a warning — cfront treats the name as the value 0, so `(SomeMissingType)fnptr` becomes an integer 0 and the call goes through a null pointer. gcc rejects it. Found in cpyext M5: a function-pointer cast silently became 0 and the program segfaulted far from the cast."
status: done
owner: claude-AC
---

# an undeclared type name in a cast is treated as `0`

- **Type:** bug (C frontend — warning where gcc errors, and the fallback value
  is dangerous) — **Track C**
- **Found:** 2026-08-03 while bringing up cpyext M5
  ([[feature-nilpy-cpyext-c-api-from-source]]).

## Measured

Cython's generated C casts a function pointer through a typedef whose name
depends on the claimed CPython version:

```c
(_PyCFunctionFastWithKeywords)__pyx_pw_5cyadd_1cyadd
```

Our `Python.h` declared `PyCFunctionFastWithKeywords` but not the private
pre-3.13 spelling with the leading underscore. cfront said:

```
pascal26:6194: warning: undeclared identifier '_PyCFunctionFastWithKeywords' used as value (treated as 0)
ok: /tmp/cy5  [code=383820B ...]
```

and the produced program **segfaulted**. gcc on the same file:

```
error: '_PyCFunctionFastWithKeywords' undeclared here (not in a function);
       did you mean 'PyCFunctionFastWithKeywords'?
```

— including the did-you-mean, which is the entire diagnosis.

## Why this is worse than an ordinary missing declaration

The name is in **type position**, inside a cast. cfront falls back to its
undeclared-identifier-as-value rule, so `(T)expr` parses as something that
yields 0 rather than as a conversion of `expr`. A function-pointer cast then
produces a null pointer, stored in a `PyMethodDef` table, and the crash happens
later, somewhere else, with nothing pointing back at the cast.

It is a warning, so it is not silent — but a warning in a 6000-line generated
file scrolls past, and the failure it predicts is a segfault at a distance.
That is the pattern `devdocs/dev/debugging-playbook.md` is built around.

## Fix

An undeclared identifier in TYPE position (a cast, a declaration specifier, a
`sizeof(T)`) should be an ERROR, not a value-position fallback. The
value-position warning can stay as it is — K&R-era code relies on it and the
corpora may depend on it — this is specifically about type position, where no
sensible fallback exists.

Worth stealing from gcc while in there: the did-you-mean over declared type
names. `PyCFunctionFastWithKeywords` vs `_PyCFunctionFastWithKeywords` is a
one-character difference and the suggestion is what makes the message
actionable.

## Gate

The cast above fails to compile with a message naming the type; a
value-position undeclared identifier still warns and compiles (so the corpora
are unaffected); zlib, sqlite, tcc, lua and quickjs still build.

## Log
- 2026-08-03 — resolved, commit c43500f47.

## Follow-up: FPC seed drift (same day)

The first landing (c43500f47) broke the **FPC seed build** — not `make`, not
`gate.sh`'s pxx half, only the seed canary:

- a duplicate `FindCTypedef` forward (its real one is in `forwards.inc`, because
  it is called from an include earlier in `compiler.pas`) — FPC: "already
  declared Public/Forward", pxx: silently fine;
- `CSuggestTypeName` used at its call site above its definition with no forward
  — pxx is lax about declaration order, FPC is not.

Both fixed by dropping the duplicate and adding the missing forward. The
standing lesson (already recorded): adding or moving a routine in `compiler/**`
needs the FPC seed checked, and `gate.sh quick`'s seed canary is what catches it.
