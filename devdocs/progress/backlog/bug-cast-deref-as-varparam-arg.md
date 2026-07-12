---
prio: 50
---

# `PChar(s)^` / cast-derefs rejected as var/untyped method-call arguments

- **Type:** bug (Pascal frontend — call-argument lvalue path) — **Track P**
  (shared parser, A's gate)
- **Status:** backlog
- **Opened:** 2026-07-12, next Synapse wall after the untyped-Pointer-deref
  expression fix ([[feature-synapse-compile-check]]).

## Symptom

Passing a deref-of-cast as a by-ref (var/out/untyped) argument fails with
`undefined variable (PChar)` — the by-ref argument path resolves a bare
IDENT (CompileLValueAddress-style) instead of parsing a full lvalue
expression:

```pascal
uses classes;
var st: TMemoryStream; s: AnsiString; x: Integer;
begin
  st := TMemoryStream.Create;
  s := 'abc';
  st.Write(PChar(s)^, Length(s));    { undefined variable (PChar) }
  x := st.Read(PChar(s)^, 3);        { same }
end.
```

`PAnsiChar` spelled out fails identically. Note the EXPRESSION-level form is
fine since the untyped-deref fix (Pointer(p)^ / PChar(s)^ as plain-proc
untyped args work — see test/test_ptr_untyped_deref.pas); the gap is the
METHOD-call by-ref argument route.

## Where hit

`external/synapse/synautil.pas:1867/1884` — `Stream.read(PAnsiChar(Result)^,
Len)` / `Stream.Write(PAnsiChar(Value)^, Length(Value))`. This is the current
wall of the whole Synapse compile.

## Acceptance

- A cast-deref (`PChar(s)^`, `Pointer(p)^`, `PByte(x)^`) is accepted wherever
  a var/out/untyped argument lvalue is expected, in BOTH the plain-proc and
  the method-call argument paths (the address of the deref is passed).
- The repro above compiles and round-trips 'abc' through the stream.
- Self-host byte-identical; test covers method + plain forms.
