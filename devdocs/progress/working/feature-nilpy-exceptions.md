---
track: N
prio: 60
type: feature
---

# NilPy: `raise` and `try` / `except`

Hangs off [[feature-nilpy-corpus-uforth]]. Characterised 2026-07-20 — neither
half exists today, despite the tokens being lexed:

```python
try:                      # error: expected expression
    print(1)
except Exception:
    print(2)

raise Exception("neg")    # error near the raise
raise Exception           # same
```

`PyKeyword` already maps `try` -> tkTry, `except` -> tkExcept, `finally` ->
tkFinally and `raise` -> tkRaise, so the lexer is done; `PyParseStatement`
simply has no rule for any of them.

## Why it matters

Exceptions ARE uforth's control flow, not an error path: `ForthThrow` carries
the Forth THROW code, `CATCH` is a `try`/`except` around a word execution, and
the conformance suite's Exception word set exercises it directly. The corpus
cannot run without this even once everything else parses.

## Shape

The shared codegen already has Pascal exceptions (try/except/finally, raise,
the EXC_FRAME machinery in `defs.inc`), so this is a frontend lowering, not
new runtime:

- `try: ... except <Class>: ...` -> the existing try/except AST, matching on
  the class the way Pascal's `on E: TFoo do` does. `except Exception:` catches
  everything, since NilPy's Exception is the root shell.
- `except <Class> as name:` binds the payload — needed for `except ForthThrow
  as e: ... e.code`.
- `raise <expr>` -> raise the constructed object. `raise` bare (re-raise) is
  worth checking against the corpus before paying for it.
- `finally` if the corpus uses it.

## Sequencing note

The Exception base is currently an empty auto-registered shell
(`PyParseClass` adds it when a class inherits from it). A user subclass with
its own ctor and fields — `class ForthThrow(Exception)` with `self.code` — has
to work, so field registration on that subclass is part of the job.

## Gate

`test-nilpy` green with a `.npy` case diffed against CPython + `--tier quick`
+ self-host byte-identical + `make fpc-check`.
