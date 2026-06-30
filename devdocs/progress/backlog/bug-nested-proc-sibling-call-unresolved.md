# Nested procedure can't call its sibling (and capturing self-recursion breaks)

- **Type:** bug (parser / symtab / static-link — correctness) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30 (found in Track B latent-bug sweep, against stable v97)

## Symptom

Two related nested-procedure defects. Both reject valid Pascal at compile time
(no codegen reached).

### 1. Sibling nested procedure is not visible

A nested procedure cannot call another procedure declared in the *same*
enclosing routine. Minimal repro (6 lines, no captures, no recursion):

```pascal
program v7;
procedure outer;
  procedure a; begin writeln('a'); end;
  procedure b; begin a; end;      { <- a is a sibling of b }
begin b; end;
begin outer; end.
```

```
pascal26:4: error: undefined variable (a)
```

The sibling's name is not in scope inside another nested routine's body.
Declaration order does not help (`a` is declared before `b`). Works fine when
the call comes from the **enclosing** routine's own body — only sibling-to-sibling
fails.

### 2. Capturing nested procedure can't self-recurse

A nested procedure that **captures an outer variable** and **recurses** is
rejected with an arity error:

```pascal
program m1;
function outer(n: integer): integer;
  var acc: integer;
  procedure inner(k: integer);
  begin
    if k>0 then begin acc := acc + k; inner(k-1); end;   { self-call }
  end;
begin acc := 0; inner(n); outer := acc; end;
begin writeln(outer(5)); end.
```

```
Candidate idx 43: paramCount = 2
  param[0] = 1
  param[1] = 1
pascal26:6: error: no overload of inner$18 matches these arguments ()
```

The candidate has `paramCount = 2` (the user param + the hidden static-link /
captured-frame arg), but the self-call site is resolved as passing `()` — the
hidden arg is not supplied, so overload resolution fails.

## Isolation matrix (all against stable v97)

| Case | capture | call from | result |
| --- | --- | --- | --- |
| self-recursion | no | self | **OK** |
| self-recursion | yes | self | FAIL — arity `()` (symptom 2) |
| sibling call | no | sibling nested proc | FAIL — `undefined variable` (symptom 1) |
| sibling call | yes | sibling nested proc | FAIL — `undefined variable` (symptom 1) |
| capturing proc | yes | enclosing routine body | **OK** |

So: the enclosing scope sees its nested procs and passes the static link fine;
a **nested proc body** does not see its sibling procs at all, and even its own
name resolves without the hidden captured-frame argument.

## Likely cause

When building the symbol scope for a nested procedure's body, the parent
routine's *other* nested procedures are not inserted into the visible scope
(only parent vars/params + the proc itself). And the self-name that *is* visible
is the bare user signature, missing the synthesized static-link parameter that
codegen adds for captures — so a same-level call resolves to the wrong arity.
Look at how nested-proc symbols are registered in `symtab.inc` / scope push in
`parser.inc`, and where the hidden static-link arg is appended to the signature
vs. to call sites.

## Acceptance

- `v7` above compiles and prints `a`.
- `m1` above compiles and prints `15`.
- Sibling calls work regardless of declaration order and regardless of capture.
- A capturing nested proc can recurse (direct and mutual).
- Self-host stays byte-identical; add a regression test
  (`test/test_nested_proc_sibling_call.pas`).
