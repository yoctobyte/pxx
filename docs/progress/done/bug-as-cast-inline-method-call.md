# bug: method call on an inline `(expr as T)` is silently dropped

- **Type:** bug (Track A — codegen) — silent no-op (method not invoked)
- **Status:** done
- **Found:** 2026-06-23, differential probe vs FPC
- **Closed:** 2026-06-23
- **Severity:** medium (a method call silently does nothing)

## Resolution (2026-06-23)

Two parser gaps (front-end only, no codegen), both surfaced by `(o as T).m`:

1. ParseFactor's parenthesised-expression postfix `.` handled only fields and
   *interface* method calls; a non-interface class/record method (`.m`) fell to
   the AN_FIELD branch — a discarded field read, never a call. Added a
   `mmi >= 0` branch that builds the class method call (static or virtual
   dispatch, Self = the grouped value), mirroring `ParseClassRecordSelectors`,
   and guarded mmi with `FindUProp` so a property still takes the field path.
   This fixed the expression form `writeln((o as T).k(21))`.
2. The *statement* form `(o as T).m;` never reached ParseFactor: a statement
   starting with `(` hit ParseStatementAST's default branch, which skips tokens
   to `;` — silently dropping it. Added a `tkLParen:` statement case that
   ParseExpr's the leading group (now resolving the call) and handles a trailing
   `:=` (also fixes `(p)^ := v` statements, previously skipped too).

Verified `(o as T).m;` -> M, `(o as T).k(21)` -> 42 (virtual), `(p)^ := 99`,
matching FPC. Controls (`t := o as T; t.m`, `T(o).m`) still work. Gate:
`make test` (self-host byte-identical — front-end only) + FPC oracle. Closes
bug-as-cast-inline-method-call.

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
