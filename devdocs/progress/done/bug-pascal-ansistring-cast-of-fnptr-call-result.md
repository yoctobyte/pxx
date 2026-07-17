---
summary: "SILENT: AnsiString(<call through a function-pointer returning PChar>) yields a garbage length"
type: bug
prio: 45
---

# `AnsiString(fp())` of a function-pointer PChar result mis-lowers — garbage length (SILENT)

- **Type:** bug (Track A — `IsNodePChar` / typecast lowering). SILENT (garbage length,
  heap over-read). Sibling of the now-fixed
  [[bug-pascal-ansistring-cast-of-cdecl-call-result]] (external direct-call variant).
- **Status:** done
- **Found:** 2026-07-17, sibling sweep after fixing the external-call variant.

## Repro

```pascal
type TPCharFn = function(n: PAnsiChar): PAnsiChar; cdecl;
function getenv(name: PAnsiChar): PAnsiChar; cdecl; external 'libc.so.6';
var fp: TPCharFn; s: AnsiString;
begin
  fp := @getenv;
  s := AnsiString(fp('PATH'));   { garbage length; direct getenv('PATH') is now correct }
end.
```

`fwd(...)` (forward-declared) and `obj.Method(...)` results cast correctly — only the
**indirect (function-pointer) call** fails.

## Root

The call is an **`AN_CALL_IND`** node (call through a proc-typed value), not `AN_CALL`.
`IsNodePChar` (`ir.inc:1494`) enumerates node SHAPES and its case 4 keys on
`ASTIVal[node]` as a **procIdx** — an indirect call has none, so no case matches →
`IsNodePChar` returns False → the cast reinterprets the raw pointer as a managed handle →
bogus length. Yet another shape the enumerator doesn't cover.

## Fix

- **Narrow:** `AN_CALL_IND` stores `ASTIVal[node] = the signature's Procs[] index`
  (`cpi`, see `ir.inc:5845`). So the fix is two parts: (1) add an `AN_CALL_IND` case to
  `IsNodePChar` that checks `ProcRetPtrElemTk[ASTIVal[node]]` (mirroring case 4); (2)
  ensure the **Pascal proc-type signature registration sets `ProcRetPtrElemTk`** the way
  cparser does for C fn-pointer sigs (`cparser.inc:3315`) — if it doesn't, that's the
  same dropped-field bug as the external-decl path, one layer over. Verify (2) first (it
  may already be set, in which case only (1) is needed).
- **Systemic (preferred):** [[refactor-centralize-managed-string-pchar-conversion]] — key
  on the node's resolved static type instead of enumerating shapes. This bug and the
  external-call bug are its two motivating instances; the refactor kills both plus every
  future shape (ternary, index, `with`-field…) at once.

## Acceptance

- The repro reports the correct length; a `test/test_*.pas` regression covers the
  fnptr-call cast.
- Gate: `make test` + self-host byte-identical.

## Log
- 2026-07-17 — resolved, commit 9118a760.
