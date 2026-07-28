---
track: A
prio: 70
type: bug
---

# A C call binds to a Pascal routine of a DIFFERENT arity, silently

cfront resolves an undeclared-or-extern C function name through `FindProc`,
which spans the C and Pascal namespaces **case-insensitively**. That is
deliberate and useful — lua's `<math.h>` `sqrt`/`sin`/`cos` bind to the RTL's
Pascal `Sqrt`/`Sin`/`Cos`, which is how a C corpus gets a math library at all.

There is no check that the two agree on anything. When they do not, the call is
compiled anyway and the failure is a crash somewhere else entirely:

- `time(NULL)` in a C unit bound to sysutils' `function Time: TDateTime` — no
  parameters, Double result — the moment the program also used sysutils
  ([[bug-c-unit-crashes-when-sysutils-is-used]]; the crash looked like a heap
  bug in third-party C for weeks);
- the same shape produced `exp(x) = e^(previous result)` in b377, because the
  argument never arrived.

Both were found only by disassembling. A one-line arity comparison would have
named either in seconds.

## What to do

At the bind site in `cparser.inc` (the `procIdx := FindProc(name)` fallback,
around the `forceSystemExternal` block), when the found proc is a PASCAL proc
(not `ProcCdecl`) and its `ParamCount` differs from the C declaration's, either

1. **warn** — cheap, keeps every current binding working, and turns a
   multi-week hunt into a compile-time line; or
2. **do not bind** — register the C name as its own proc, so an unresolved
   extern surfaces at link time instead.

(1) first, since it cannot break a corpus. Measure how many hits the existing
corpora produce; if the answer is zero or all-genuine, escalate to (2).

A type-compatibility check on the parameters is the obvious next rung, but
arity alone catches both bugs seen so far.

## Known collision surface

Cross-namespace names that exist on BOTH sides today (crtl headers vs
`lib/rtl/*.pas` globals), collected mechanically:

```
abs ceil close copy cos cosh exp floor fmod gethostbyname htonl htons hypot
isspace log10 log2 mkdir ntohl ntohs open poll read remove sin sinh sqrt
strcat strlen tan tanh write
```

Some are intentional (the math family, already routed through `__crtl_` macros
where the convention differs), some are harmless (Pascal METHODS do not
collide — only globals do), and some are latent copies of the `time` bug.
The diagnostic above is what tells them apart without auditing the list by hand.
