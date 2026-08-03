---
track: P
prio: 80
type: bug
status: done
owner: claude-P@opus5
---

# A procedural variable in a value context takes its ADDRESS instead of calling it

- **Type:** bug (Pascal frontend semantics, silent wrong value) — **Track P**
- **Found:** 2026-08-02 by the Track B agent, narrowing the Synapse/OpenSSL
  crash left open on [[feature-real-dynlib-loader]] item (d). Filed, not fixed:
  the Pascal frontend lives in the shared `lexer.inc`/`parser.inc`, which is not
  Track B's to edit.

## Minimal repro

```pascal
program pv;
{$MODE DELPHI}
type TF = function: Pointer; cdecl;
var fp: TF; magic: Pointer;

function Impl: Pointer; cdecl;
begin Impl := magic; end;

function ViaBareName: Pointer;
begin
  if Assigned(fp) then Result := fp else Result := nil;
end;

begin
  magic := Pointer(Int64($DEADBEEF));
  fp := @Impl;
  writeln(Int64(ViaBareName));
end.
```

| | `Result := fp` yields |
| --- | --- |
| **FPC 3.2.2, `{$MODE DELPHI}`** | `3735928559` — the value `fp()` returns (**called**) |
| **pxx `--mimic-fpc`** | `4198544` — `@Impl` (**address taken, never called**) |

A procedural variable named in a context that wants a VALUE must be called.
Taking its address is what `@fp` is for. Note `fp()` with explicit parens is
already correct in pxx — only the bare-name form is wrong, so the two spellings
disagree, and the wrong one is the one real Delphi code uses.

Verified against FPC in `{$MODE DELPHI}` specifically because that is the mode
the affected unit declares; the oracle was run, not remembered.

## Why this is bad rather than obscure

The wrong result is a **valid pointer**, so nothing errors. It is assigned,
returned, and passed onward, and the program dies far away — the exact
plausible-wrong-value shape `devdocs/dev/debugging-playbook.md` describes. And
the idiom is not exotic: "load a function pointer at runtime, wrap it in a
function that calls it" is how every dynamic-binding layer in Delphi-family
code is written, so this affects any such library, not just the one below.

Related but distinct: [[frank2-paramless-name-semantics]] covers a FUNCTION's
own name inside its body (bare name = result variable). This is a procedural
VARIABLE in an expression, which is a different rule with the opposite answer.

## The chain it was found through, end to end

Synapse `external/synapse/ssl_openssl3_lib.pas:613`:

```pascal
function SslMethodTLS: PSSL_METHOD;
begin
  if InitSSLInterface and Assigned(_SslMethodTLS) then
    Result := _SslMethodTLS        { <- procvar in a value context }
```

1. FPC calls it and returns OpenSSL's `SSL_METHOD*`. pxx returns
   `@TLS_method` — the address of the loader-resolved function itself.
2. Synapse hands that to `SSL_CTX_new`.
3. libssl dereferences it as a method table and dies:
   `call *0xb8(%r12)` with `rdi`/`rsi` `0`.

Confirmed by simulation rather than inference — driving OpenSSL 3 directly
through our own `dlopen`:

```
SSL_CTX_new(TLS_client_method())   -> ctx non-nil, fine
SSL_CTX_new(@TLS_client_method)    -> SEGFAULT
```

## What this clears

The 2026-07-31 note on [[feature-real-dynlib-loader]] guessed this crash was "a
marshalling or symbol-resolution fault on the indirect-call path, i.e. Track A
again". **That is ruled out.** Driving OpenSSL 3 directly through our `dlopen`
works completely: `OPENSSL_init_ssl` returns 1, `TLS_method` and
`TLS_client_method` resolve, and `TLS_client_method()` / `SSL_CTX_new()` /
`SSL_new()` all return non-null. Our loader, our `dlsym`, and our cdecl
indirect-call marshalling are all fine against the same library. The fault is
this frontend semantics bug alone.

## Gate

The repro above returns FPC's value; `fp` and `fp()` agree; `@fp` still yields
the address. Then Synapse's `SSLDoConnect` reaching a real TLS handshake, which
is [[feature-real-dynlib-loader]] item (d) and is the end-to-end check.

## Resolution 2026-08-03 (claude-P@opus5)

Fixed at the `AN_ASSIGN` lowering choke point (`ir.inc`), chosen for the same
reason the enum-identity check already sits there: **every syntactic form of
assignment funnels through that node**, so one rule replaces edits at ~20
assignment sites — which is exactly the shape this repo has been bitten by
before (the hand-built-call-args landmine).

A bare procvar RHS becomes an `AN_CALL_IND` with the symbol's `SymProcSig`
signature, no arguments, and the signature's result type — the identical node
`fp()` already produced, so the two spellings now agree by construction rather
than by coincidence.

Deliberately conservative, because a wrong call here would be as silent as the
bug. It fires only when:

- the RHS is a **bare** procvar identifier (`@fp` is AN_ADDR, `fp()` is already
  AN_CALL_IND — neither matches);
- the signature takes **no parameters**, since a bare name supplies none;
- the LHS is an identifier we can **positively** see is not itself proc-typed,
  so `fp := f2` keeps copying the pointer and a field/indexed target is left
  alone rather than guessed at.

### Verified against FPC, not against expectation

The ticket's repro, run under both:

| | `Result := fp` yields |
| --- | --- |
| FPC 3.2.2, Delphi mode | 3735928559 |
| pxx `--mimic-fpc`, before | 4198544 (`@Impl`) |
| pxx `--mimic-fpc`, after | **3735928559** |

`test/test_procvar_value_context.pas` (gated) pins the rule and all four
exceptions — `fp()` agreeing with the bare name, `fp2 := fp` copying the
pointer, `@fp`, `Assigned(fp)`, and a parameterised signature staying a pointer
copy. It compiles and prints the same line under **FPC and pxx**.

FPC's own diagnostics were used as the oracle for the exceptions too: it rejects
`Pointer(gp)` for a parameterised `gp` with "Wrong number of parameters
specified for call to `<Procedure Variable>`", confirming it reads a cast
operand as a call.

`tools/gate.sh quick` GREEN.

### Deliberate remainder, filed

Value contexts **other than an assignment** still yield the address —
`Int64(fp)` in a `writeln` argument, a procvar passed to a non-procvar
parameter, a comparison against a non-procvar. At the assignment node both
sides' types are known and the exceptions are decidable; in a general expression
the parser has no expected-type channel yet, so this took the decidable half
rather than guess at the rest. Filed as
[[bug-pascal-procvar-value-context-outside-assignment]] (prio 60) with the full
Delphi rule and the fix shape.

The Synapse chain this was found through — `Result := _SslMethodTLS` — is the
assignment form, so [[feature-real-dynlib-loader]] item (d) is unblocked by this
alone; the end-to-end TLS handshake check belongs there.

## Log
- 2026-08-03 — resolved, commit f14a4679c.
