# bug: method call on an inline `(expr as T)` is silently dropped

- **Type:** bug (Track A — codegen) — silent no-op (method not invoked)
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** medium (a method call silently does nothing)

## Symptom

Calling a method directly on a parenthesized `as`-cast produces no call:

```pascal
type ta = class end; tb = class(ta) procedure m; end;
procedure tb.m; begin writeln('M'); end;
var o: ta;
begin o := tb.create; (o as tb).m; end.
{ fpc: M    pxx: (prints nothing — m is never called) }
```

## What works (controls)

- Assign then call: `t := o as tb; t.m;` → `M`.
- Hard cast inline: `tb(o).m;` → `M`.
- The `is`/`as` operators themselves work elsewhere (`if o is tb` is correct).

So only the combination `(<expr> as T).method` mis-lowers — the `as` result is
not used as the call's receiver, and the call is dropped silently.

## Expected

`(o as tb).m` dispatches `m` on the cast reference (FPC: `M`).

## Repro

`tools/fpc_diff_probe.sh` (`as-inline-call`).
