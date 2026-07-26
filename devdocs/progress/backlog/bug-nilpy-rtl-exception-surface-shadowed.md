---
summary: "nilpy: pylib's Exception shadows sysutils' identical declaration, so RTL units fail on CreateFmt/FMessage"
type: bug
track: N
prio: 60
---

# nilpy: importing an RTL unit fails on `Exception.CreateFmt`

- **Type:** bug (Nil-Python frontend / pylib class shadowing) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26. Second half of what blocked `import json`; the FIRST
  half (TVarRec unresolved for the nilpy path) is fixed.

## Repro

```python
import json          # or any RTL unit reaching sysutils
```
```
pascal26:486: error: class method not found: CreateFmt
  near: else raise EConvertError.CreateFmt('"%s" is not a valid boolean' ...
```

## Cause

pylib declares its own Python-shaped `Exception` (msg + Create) so that
`except ValueError:` and `raise ValueError(...)` work and pylib itself can raise.
A `.npy` program pulls pylib BEFORE any imported unit, so when sysutils declares
its own `Exception` (FMessage, FHelpContext, Create, **CreateFmt**, Message,
HelpContext) that declaration is silently shadowed — see
[[bug-pascal-duplicate-class-name-silently-shadows]] — and sysutils' descendants
(EConvertError, …) plus its method bodies are compiled against the Python class,
which has neither CreateFmt nor FMessage.

## What I tried, and the trap to avoid

Adding the Pascal surface (CreateFmt with a self-contained %-formatter, FMessage,
Message/HelpContext properties) onto pylib's Exception made `import json` compile
and Python exceptions still caught — but `print(e)` for a
`raise ValueError("mine")` printed EMPTY once an RTL unit was imported, while
printing "mine" without the import. Syncing both fields in every constructor did
NOT fix it, so the read path shifts too. That is a message-loss regression, i.e.
silent wrong output, so it was reverted rather than shipped. Whoever picks this up
must test BOTH: an RTL unit imported, and a Python exception's message printed.

## Shape

One Exception class serving both surfaces, rather than two that shadow. Either:
- pylib declares the FULL sysutils surface (fields AND methods) and sysutils'
  declaration is recognised as the same class rather than shadowed; or
- pylib's Python exception hierarchy descends FROM sysutils.Exception when that
  unit is present, so `msg` becomes a view over `FMessage` and there is one
  storage.
The second is cleaner and needs the shadowing bug fixed first.

## Gate

`make test-nilpy` green with a `.npy` case that imports an RTL unit AND prints a
caught Python exception's message, + `--tier quick` + self-host byte-identical.
