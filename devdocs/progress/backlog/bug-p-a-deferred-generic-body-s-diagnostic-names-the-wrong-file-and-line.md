---
slug: bug-p-a-deferred-generic-body-s-diagnostic-names-the-wrong-file-and-line
title: "A deferred generic body's diagnostic names the wrong file AND the wrong line"
track: P
prio: 60
type: bug
status: new
blocked-by: []
owner: ""
summary: "Compiling generics.collections.pas reports `unknown type: TKey` `in: generics.defaults.pas` at line 78. TKey appears ZERO times in generics.defaults.pas and 65 times in generics.collections.pas; defaults.pas:78 contains no TKey and no SizeOf, while the `near:` context it prints matches collections.pas:1309-1310. Both the file and the line are wrong -- the current-unit pointer appears not to be switched when a deferred generic body is compiled. Sends whoever picks up a generics failure to the wrong file first; cost frankB a pass."
---

# A deferred generic body's diagnostic names the wrong file and line

Found by frankB while running rung 6b of [[feature-pascal-corpus-expansion]].
Measured at HEAD `4f42b78b9` against pinned `faf762981c3c` — not read.

## What it prints

Compiling `generics.collections.pas`:

```
unknown type: TKey
in: generics.defaults.pas   line 78
near: ) * SizeOf ( T ) >>> ) ; FillChar
```

## Why all three parts of that are wrong

| claim | check |
| --- | --- |
| the error is in `generics.defaults.pas` | `TKey` appears **zero** times in that file, and **65** times in `generics.collections.pas` |
| …at line 78 | `defaults.pas:78` is `function Equals(constref ALeft, ARight: T): Boolean;` — no `TKey`, no `SizeOf` |
| the `near:` context | matches `generics.collections.pas:1309-1310` |

So the **position** is real and points into `collections.pas`; only the *file
attribution* and the line number are wrong. The `near:` text is the one field
that survived, which is why the mismatch is detectable at all.

## Likely mechanism, unconfirmed

The current-unit pointer is not switched when a **deferred generic body** is
compiled: the body is parsed in the context of the unit that *declared* the
template, so the diagnostic reports that unit's file and a line number from the
wrong table, while the token stream — and therefore `near:` — is the
instantiating unit's. Do not take this as the diagnosis; it is where to start.
`PXXDBG=n.locals` / `a.ast:<proc>` and the deferred-body path in
`pasparser_generic.inc` are the instruments.

## Why p60 and not the error-reporting default

CLAUDE.md defers *parity* of diagnostics — "our message differs from FPC's" — as
low prio. **This is not parity.** The diagnostic is not differently worded, it is
**false**: it names a file that does not contain the symbol. That misroutes
debugging rather than merely reading differently, and it does so on the exact
path the p75 corpus campaign runs. frankB lost a pass to it before checking the
grep counts, and it will cost the same to everyone who hits a generics failure in
a multi-unit build.

## Gate

A test whose expected output names the **instantiating** file. Assert the file
attribution, not only that an error occurs — the error occurring is what happens
today.
