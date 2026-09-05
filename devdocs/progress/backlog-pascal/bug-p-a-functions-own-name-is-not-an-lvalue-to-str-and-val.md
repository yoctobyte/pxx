---
prio: 45
track: P
summary: "`Str(l, G)` and `Val(s, G)` inside `function G` fail with `undefined variable (G)`, while the SAME function name passed to a USER procedure's var parameter works. So this is not `a function's own name is not an lvalue` -- that path is fine -- it is the INTRINSIC var-argument path specifically, which resolves its destination by a route that does not know about the own-name-is-Result rule. `Result` works in both, and is the workaround. Two paths for one concept and the second one is the broken one. BLOCKS FPC'S erroru.pp, which is the helper unit behind five conformance skip rows: after ErrorAddr/TFPCHeapStatus/GetFPCHeapStatus landed (that was the recorded blocker) erroru.pp still does not compile, and this is now the only thing stopping it. `getsize` there is a nested function doing exactly `Str(l, getsize); getsize := getsize + ' bytes'`."
---

# A function's own name is not an lvalue to `Str` and `Val`

- **Type:** bug — Track P (Pascal frontend)
- **Status:** backlog, unclaimed
- **Found:** 2026-09-05 (frankB), unblocking the conformance `erroru` trio

## Repro

```pascal
program o2;
function G: string; begin Str(7, G); end;
begin WriteLn(G); end.
```
`error: undefined variable (G)`

## The boundary — measured, and it moved the diagnosis twice

| shape | result |
| --- | --- |
| own name to a USER `var` parameter — `Fill(G)` | **works**, prints `x` |
| own name to `Str` — `Str(7, G)` | **refused** |
| own name to `Val` — `Val('7', G)` | **refused** |
| `Result` to a user `var` parameter | works |
| `Result` to `Str` | works, prints `7` — **the workaround** |
| own-name read/write with no var argument at all — `G := G + 'b'` | works |

Two readings had to be discarded to get here, and both are worth recording
because both looked settled:

1. **"It is a NESTED function problem."** The first sighting was
   `undefined variable (getsize$50501)` — a mangled nested name — inside
   erroru.pp's nested `getsize`. But a nested function reading and writing its
   own name with no `Str` works fine, and a TOP-LEVEL function with `Str` fails.
   The mangling in the message is what made nesting look causal; it is only
   telling you which scope the lookup happened in.
2. **"A function's own name is not an lvalue."** Also false — it is one, to a
   user procedure's `var` parameter, in the same program.

## Why it matters beyond the shape

This is the last thing between us and FPC's `erroru.pp`, the helper unit behind
**five conformance skip rows** (`tobject1`, `tstring2`, `tstring5` and two
more). Its recorded blockers — `ExitCode`, `System.ErrorAddr`,
`TFPCHeapStatus`, `GetFPCHeapStatus` — are all resolved as of 2026-09-05
(`ExitCode` had in fact been present for a while and the skip prose was stale).
`erroru.pp` now reaches its `getsize` helper and stops there, on this and
nothing else.

## Where to look

The general lvalue path already gets this right, so the fix is almost certainly
to route the intrinsic's destination argument through the same resolution rather
than to add own-name handling to a second place —
`devdocs/dev/normalise-dont-special-case.md` is the relevant north star, and
this is its stock shape: a construct reachable through two paths, where the
second path is the one that stayed broken. Grep for `Val` when fixing `Str`;
they fail identically and are presumably siblings in the same argument handler.
