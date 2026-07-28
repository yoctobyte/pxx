---
track: B
prio: 70
type: bug
---

# sysutils and pylib both declare `Exception`, and their shapes had diverged

Any program that pulled **sysutils before pylib** failed to compile with

```
error: undefined variable (msg)
```

reported at a line inside pylib, with nothing wrong there. It took out
`uses json` in any Pascal program and `examples/net/httpdemo.pas` on every
target (http.pas lists `sysutils` ahead of `base64`, and base64 pulls pylib).

## Cause

`Exception` is deliberately shared program-wide
(`ClassNameIsDeliberatelyShared` in symtab.inc — a NilPy `except Exception:`
must catch what an RTL unit raises, so both declarations have to resolve to ONE
row). Whichever unit registers first owns that row.

The two declarations were not interchangeable:

| | message storage | views |
| --- | --- | --- |
| pylib | field `msg` | `FMessage`, `Message` properties over it |
| sysutils | field `FMessage` | `Message` property over it |

With pylib first everything worked. With sysutils first, pylib's own method
bodies (`constructor Exception.Create` does `msg := m`) compiled against
sysutils' class, which has no `msg` — hence the error, at a line the
application never wrote.

## Fix

sysutils' `Exception` now mirrors pylib's member for member: field `msg` first,
`FHelpContext` second, `FMessage`/`Message` as properties over `msg`. Either
registration order now yields a row both units' bodies compile against, and the
field ORDER matches so the layout is the same whichever row wins.
`lib/rtl/json.pas` and `lib/rtl/pathlib.pas` also list pylib first now, with a
note saying why.

Keep the two declarations in step. The order-dependence itself is a design
question tracked by [[decide-class-namespace-scoping]] — this ticket only makes
the two shapes agree.
