---
track: P
prio: 35
type: bug
blocked-by: []
summary: "`TFn(p)(args)` — calling straight through a procedural-type cast — is `unexpected token`, where FPC compiles and runs it. Assigning the cast to a variable first and calling that works, so the capability is present and only this spelling is refused. Hit twice while writing repros for the rtl-generics constant-initializer walls."
status: working
owner: opus5-frank1
---

# Cannot call directly through a procedural-type cast

- **Status:** done

Found 2026-08-16 while clearing the record-constant walls in
[[feature-pascal-corpus-generics]]. Not folded into those fixes: it is a
different mechanism (expression-level call syntax, not constant initializers) and
they are green without it.

## Measured

```pascal
type TSelfFn = function(s: TB): LongInt;
var f: TSelfFn;

f := TSelfFn(V.QI); writeln(f(o));   { works — pxx and FPC agree }
writeln(TSelfFn(V.QI)(o));           { pxx: error: unexpected token }
```

| form | FPC 3.2.2 | pxx |
| --- | --- | --- |
| cast into a variable, then call | `5` | `5` |
| call directly through the cast | `5` | **`unexpected token`** |

Same for a plain `Pointer` const: `TPr(PP)()` is refused, `f := TPr(PP); f()` is
fine.

## Why it is a real gap rather than a style question

The capability is entirely present — the cast is legal, the resulting value is
callable, and one extra local makes it work. Only the direct spelling is refused,
so this is a parse-level hole and not a missing feature. It is also the natural
way to write a dispatch through a hand-built VMT, which is exactly the code that
led here: rtl-generics reaches its comparers this way.

Cost when it bites: the diagnostic is `unexpected token` with no indication that
a temporary would fix it, and it surfaces on the *call* line rather than at the
cast, so it reads as a problem with the argument list.

## Likely shape

After a type-cast expression is parsed, the postfix loop does not consider `(`
as a call on the result — the same postfix-continuation question as indexing or
`.field` on a call result. Worth checking whether `(` after a cast is handled for
any other receiver shape before adding a case; if the postfix loop is the single
place, this is one arm rather than a new path.

Related in kind (a construct reachable through two shapes, one wired and one
not): [[project_nilpy_lvalue_vs_selector_path_must_both_know]].

## Gate

Both rows above matching `fpc -O1 -Mobjfpc`, for a procedural cast of a record
field, a scalar const and a plain variable; `gate.sh quick`; self-host
fixedpoint.

## 2026-08-17 — reproduced, scoped, PARKED. The filed hypothesis is doubtful.

Reproduced at HEAD with a 12-line repro (`TFn(p)(21)` and `TFn(V.F)(21)`, both
`unexpected token`; `f := TFn(p); f(21)` fine). FPC 3.2.2 `-O1 -Mobjfpc` prints
42 for all three.

**Correcting my own filing.** This ticket says: *"Worth checking whether `(`
after a cast is handled for any other receiver shape before adding a case; if
the postfix loop is the single place, this is one arm rather than a new path."*
Half an hour of measurement says the antecedent is probably false — there is no
single place.

The cast machinery in `ParseFactorCore` already forks at least four ways: scalar
casts resolved by NAME (`pointer`/`int64`/`integer`/… at ~15224), a
**special-cased `PChar(s)` path that hand-rolls its own `[` subscript loop**
(~15206), the type-ALIAS path (`FindTypeAlias`, ~13073 / ~15024), and enum
types. The `PChar` one is the tell, and its own comment says why it exists:

> *"the shared postfix loop's AN_PTR_CAST branch reads AliasElemTk[ASTIVal],
> which the -2 adapter has no entry for, so handle the subscript here."*

So a previous author already found that the shared postfix loop does not reach
one cast flavour, and solved it by hand-rolling that postfix **inside** that
flavour. That is direct evidence the call-postfix will have the same shape: not
one arm on a shared loop, but a decision about whether to keep adding per-flavour
postfix handling or to normalise the cast paths first.

That makes this a `normalise-dont-special-case` question, not a one-liner —
which is exactly the class the playbook says to diagnose and park rather than
microfix. **Whoever picks this up: start by counting the cast paths and deciding
whether they should be one, not by adding a fifth `(`-handler.**

**Why parked here:** taken by the coordinator session as a test of holding a
ticket alongside the role, under a stated constraint that the ticket be
already-diagnosed (execution, not investigation). It is not — my own filing was
a hypothesis wearing a diagnosis's clothes. Parking it is the constraint working,
not the ticket being hard.

## Outcome — 2026-08-27

The parked instruction was *"start by counting the cast paths and deciding
whether they should be one, not by adding a fifth `(`-handler."* Counted. **The
answer is one, and it is not a compromise.**

### The count

A procedural type is always user-DECLARED, so it is always a type **alias**. The
other cast flavours the parking note enumerates — the builtin scalar names
resolved by `BuiltinScalarTypeKind`, the hand-rolled `PChar` adapter, enum
types, `string` — can never yield a callable value. So the call postfix has
exactly **one possible receiver shape**, and putting it at the alias-cast site
is not a fifth per-flavour handler; it is the only place it could go.

Measured before writing anything, which is what settles it: **`^`, `.field` and
`[i]` after a cast already work.**

```pascal
writeln(PR(p)^.A);      { 5  }
writeln(PArr(pa)^[2]);  { 9  }
writeln(TR(r).B);       { 6  }
```

So the postfix machinery already reaches casts and `(` was the single missing
one — the ticket's ORIGINAL hypothesis, which the parking note doubted. The
`PChar` special case the note read as counter-evidence is about a different
thing: its own comment says the shared loop's `AN_PTR_CAST` branch reads
`AliasElemTk[ASTIVal]` and the `-2` adapter *has no alias row*, so that flavour
hand-rolls the subscript it cannot look up. That is one flavour's node shape,
not a missing loop — and it is one of the flavours that can never be called.

### What landed

- The `C4` pointer-type-alias cast site in `ParseFactorCore` now takes a `(`
  when `AliasProcSig[aliasIdx] >= 0`, building the same `AN_CALL_IND` the
  proc-var path builds. A method-pointer alias is `tyRecord` (16 bytes of
  `{Code, Data}`) and the cast is a **retype** of the operand, which records
  already carry by address; the pointer form gets the `AN_PTR_CAST` wrapper.
  Same split the record arm immediately below already states for the non-call
  case.
- **`BuildIndirectCallAST`** — the indirect-call argument loop was written out
  **twice** already (`ParseProcVarCallAST` and the anonymous proc-var arm inside
  `ParseLValueAST`), and this needed a third. Two is a smell, so the three are
  now one and the callers differ only in how they produce the callee node, which
  is the only thing that actually differs between them. The change is net
  smaller than the feature.

The C frontend had already solved the same problem its own way
(`cparser.inc:3648` reads `AliasProcSig` for `(ft*)e` → `(*..)()`), which is
independent confirmation that keying on the alias's signature is the right
handle.

### Measured

`test/test_call_through_a_procedural_cast.pas` (+ `.expected`, wired into
`test-core`), 9 rows byte-identical to `fpc -O1 -Mobjfpc` 3.2.2:

| form | before | after / FPC |
| --- | --- | --- |
| `f := TFn(p); f(21)` | 42 | 42 |
| `TFn(p)(21)` | **unexpected token** | 42 |
| `TFn(V.F)(21)` — record field | **unexpected token** | 42 |
| `TFn(arr[1])(21)` — array element | **unexpected token** | 42 |
| `TFn(@Twice)(21)` — address-of | **unexpected token** | 42 |
| `TFn(p)(TFn(p)(5))` — nested | **unexpected token** | 20 |
| `TProc0(@Bump)()` ×2 — no result, as a statement | **unexpected token** | 2 |
| `m(5)` / `TMethFn(m)(5)` — method pointer | 105 / **unexpected token** | 105 / 105 |

The five NilPy callable tests (which share `ParseProcVarCallAST`, and one of
which wraps its result for heap callables) are byte-identical after the
deduplication.

### Gate

`make compiler/pascal26` byte-identical (e36f58b15737) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 · c-conformance 220/0 · fgl 7/7.

## Log
- 2026-08-27 — resolved, commit 8a1b387b3.
