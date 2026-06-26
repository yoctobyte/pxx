# A pointer dereference `p^` is rejected as a `var`/by-ref argument

- **Type:** bug (parser / argument binding)
- **Status:** backlog (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** [[feature-synapse-compile-check]] — building `lib/rtl/sockets.pas`
  (`fpSelect` wanted to pass `readfds^` / `exceptfds^` to the `FD_*` helpers).

## Symptom

Passing a dereferenced pointer `p^` as a `var` (by-reference) argument errors:

```pascal
type TR = record b: LongWord; end; PR = ^TR;
procedure setit(var r: TR); begin r.b := 5; end;
var rr: TR; p: PR;
begin p := @rr; setit(p^); end.
```
→ `error: by-reference argument must be a variable`

`p^` is a valid l-value — FPC accepts it as a `var` argument. Assigning through
the deref (`p^ := x`, `p^.field := x`) works; only using it as a by-ref *argument*
fails.

## Impact / workaround

Idiomatic FPC code passes record-pointer derefs to `var`-param helpers freely.
In `lib/rtl/sockets.pas` `fpSelect` this was worked around by reading the record
fields directly off the pointer (`readfds^.bits[i]`) instead of calling
`fpFD_ISSET(.., readfds^)`, and inlining `fpFD_ZERO(exceptfds^)`. Equivalent and
acceptable there, but the general gap will bite other RTL/Synapse code.

## Fix

In argument binding, treat a pointer dereference `p^` (and `p^.field`,
`p^[i]`) as an addressable l-value eligible for a `var`/`out`/untyped parameter —
the same l-value test that already allows `arr[i]` and `rec.field`.

## Done when

- `setit(p^)` compiles; the `var`-arg l-value set includes pointer derefs.
- Regression test under `make test`.
- Self-host fixedpoint byte-identical.

## Resolution (2026-06-25, Track A)

Fixed. Two by-ref l-value checks in `parser.inc` (the Delphi-bare-proc call path
~4738 and the statement-call path ~7973) accepted only `AN_IDENT`/`AN_INDEX`/
`AN_FIELD`; added `AN_DEREF`. `IsASTLValue` (ir.inc:952) and the arg-lowering
addressing path already handled `AN_DEREF`, so no codegen change was needed —
just the parser gate relaxation. Covers `p^`, `p^.field`, `p^[i]`.

Test: `test/test_ptr_deref_vararg.pas` (in `make test`), prints `5 7 7`.
Verified x86-64 + i386/aarch64/arm32 (all `5 7 7`). Self-host byte-identical.
