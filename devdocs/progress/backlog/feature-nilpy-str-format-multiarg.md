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

## Next step

Find how the str-method path marshals a SECOND argument (PyParseStrMethod
builds the AN_ARG chain; the -6 arity case is where format lands) and compare
with a two-argument str method that works — `.rjust(w, fill)` is the one to
diff against, since it takes two and is fine.

Named/index fields (`{name}`, `{0}`) are also unimplemented; the placeholder
walk in pylib's PyFormatApply handles positional `{}` and `{:spec}` only.
