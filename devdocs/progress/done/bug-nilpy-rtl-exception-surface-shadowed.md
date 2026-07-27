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

## FIXED (2026-07-27)

pylib's `Exception` now carries the sysutils surface on ONE storage:

```pascal
  Exception = class
  public
    msg: AnsiString;
    FHelpContext: Integer;
    constructor Create(const m: AnsiString);
    constructor CreateFmt(const m: AnsiString; const args: array of const);
    property FMessage: AnsiString read msg write msg;
    property Message: AnsiString read msg write msg;
    property HelpContext: Integer read FHelpContext write FHelpContext;
  end;
```

The trap this ticket warned about is exactly what the PROPERTIES avoid. `print(e)`
reads the `msg` FIELD — the frontend synthesises that field access directly
(pyparser's PyReprContainer and the `str(e)` path) — so `msg` has to stay the
field and every Pascal-side name has to be a view on it. Two synchronised fields
put the Pascal write in one place and the Python read in the other, which is how
the message came back empty.

CreateFmt is implemented IN pylib, not borrowed from sysutils: a declaration in
pylib needs an implementation in pylib (`unresolved forward: Exception.CreateFmt`
otherwise), and pylib must not depend on sysutils, since pylib is pulled into
every .npy. It supports `%s`, `%d` and `%%` — every spec the RTL's own raise sites
use — and leaves an unsupported spec VERBATIM rather than guessing, so a wrong
message shows up as a stray `%spec` instead of silently dropping an argument.

Verified both directions in one test, `test/test_nilpy_rtl_exception_surface.npy`:
a Python `raise ValueError("mine")` still prints `mine` with an RTL unit imported,
and `su.StrToInt("abc")` arrives as `caught: "abc" is an invalid integer` —
formatted, i.e. CreateFmt really ran.
