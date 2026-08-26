---
slug: bug-c-a-ternary-cannot-be-the-callee-of-a-call
title: "A ternary cannot be the callee of a call: `(c ? f : g)(args)`"
track: C
prio: 50
type: bug
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-26
commit: PENDING-COMMIT
summary: "CNodeProcSig is a chain of arms, one per node shape — AN_IDENT, AN_PROCADDR, AN_CALL, AN_CALL_IND, AN_INDEX, AN_FIELD, AN_PTR_CAST, AN_COMMA — and AN_TERNARY was not among them, so `(c ? f : g)(args)` died as `Expected: ), but got:` at the `?`. busybox opens libbb/copy_file.c with exactly that. Fixed by RECURSING like the AN_COMMA arm rather than adding a ninth shape."
---

# `(c ? f : g)(args)`

Found compiling busybox 1.37.0, alongside
[[bug-c-logical-not-is-not-folded-in-a-constant-expression]].

## Repro

```c
static int add(int a, int b) { return a + b; }
static int sub(int a, int b) { return a - b; }
int main(void) { int p = 1; return (p ? add : sub)(7, 3); }
```

```
Expected: ), but got:  (Kind: 74, Line: 3)
pascal26:3: error: unexpected token
```

Measured which parenthesised callees pxx already accepted — the gap is narrow
and precise:

| form | before |
| --- | --- |
| `add(7, 3)` | ok |
| `fp(7, 3)` | ok |
| `(*fp)(7, 3)` | ok |
| `(fp)(7, 3)` | ok |
| `(add)(7, 3)` | ok |
| `(p ? fp : fp)(7, 3)` | **refused** |
| `(p ? add : sub)(7, 3)` | **refused** |

busybox, `libbb/copy_file.c:93`:

```c
if ((FLAGS_DEREF ? stat : lstat)(source, &source_stat) < 0) {
```

`coreutils/stat.c` has the same shape.

## The fix, and why it is not a ninth arm

`CNodeProcSig` answers *"what is the call signature of this node, and which node
carries the address"*, as a flat chain of `else if ASTKind[inner] = …` arms —
AN_IDENT, AN_PROCADDR, AN_CALL, AN_CALL_IND, AN_INDEX (two spellings), AN_FIELD,
AN_PTR_CAST. Eight shapes for one question, which is the smell
`root-cause-over-microfix.md` names.

The AN_COMMA arm at the top does something different: it **recurses**, because
`(a, fn)(x)`'s callee is itself a function-pointer expression. A ternary is the
same situation, so it gets the same treatment:

```pascal
if ASTKind[inner] = AN_TERNARY then
begin
  if ASTRight[inner] >= 0 then
  begin
    Result := CNodeProcSig(ASTLeft[ASTRight[inner]], commaCallee);
    if Result < 0 then
      Result := CNodeProcSig(ASTRight[ASTRight[inner]], commaCallee);
  end;
  Exit;
end;
```

C requires the two arms to have compatible types, so either supplies the
signature; ask the then-arm and fall back to the else-arm, because one may be a
null pointer constant that carries none. The callee stays the **whole** ternary
node, so the condition is still evaluated and the arm selected at run time —
`AN_CALL_IND` evaluates its callee node as a value, which is exactly what the
comma arm already relies on.

Every shape the chain knows is legal in a ternary arm, so recursion gets all of
them at once and adds nothing to maintain in step.

## Measured

| check | result |
| --- | --- |
| repro | `10`, matching gcc |
| `coreutils/stat.c` | refused → **compiles** |
| `libbb/copy_file.c` | past the ternary; now fails later at line 351 (`expected C expression`), a different gap |
| `run_c_conformance.sh` | 220 pass / 0 fail — baseline |
| self-host | converged after 1 round |
| `gate.sh quick` | GREEN |

`coreutils/test.c`, `editors/ed.c` and `util-linux/acpid.c` were filed with this
one on a shared symptom string and are **not** this bug: their `Expected: )` is
`Kind: 79`, not the ternary's `Kind: 74`, and all three stop at busybox's
`INIT_G()` / `INIT_S()` macro. Separated rather than assumed.

## Gate

`test/cternary_callee.c`, gcc -O0 oracle, wired into `test-core`: bare function
names and function-pointer variables in both arms, a ternary nested inside the
else-arm so the recursion has to go more than one level, and the condition
evaluated exactly once.

That last row is sequenced across two `printf`s on purpose. Written as one call
it read `4 0` under gcc and `4 1` under pxx — argument evaluation order within a
single call is **unspecified** in C, so the single-printf form tests the wrong
thing and both compilers are right.
