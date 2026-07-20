---
track: B
prio: 45
type: feature
blocked-by: [feature-rtti-field-reflection]
---

# lib pyexec: a real exec() for Python-subset source (library, two engines)

- **Track:** B (library — language-neutral). Consumer:
  [[feature-nilpy-corpus-uforth]]. Depends on
  [[feature-rtti-field-reflection]] for the host bridge.

`exec(src, env)` as a LIBRARY, semantics matching CPython's explicit-dict
form (which is exactly how uforth calls it): no ambient scope capture, the
host passes name -> value bindings; values are variants (int/float/str/
list/dict/object-ref/bound-method).

## Contract (censused from uforth's 134 PYTHON blocks — all parse)

Statements: assign/augassign, if/elif/else, while/for(+break), def, return,
raise, del, expression statements. Expressions: arith/bit/compare/boolop,
calls, attribute access, subscripts incl. slices, f-strings, isinstance,
ternary, tuple/list/dict literals, len/int/print builtins. Sane
restrictions: NO import, NO class definitions, NO exec-in-exec, explicit
env only.

## Two engines, shared front

1. **Front**: tokenizer + parser -> AST, cached per source string (blocks
   run per-CALL in uforth's inner loop — SWAP executes millions of times in
   the conformance suite; parse exactly once).
2. **Engine 1, tree-walker** (ships first): walks the AST over variants;
   host object access (vm.here, vm.memory[i], push(x)) resolved through
   field/method RTTI. The correctness reference.
3. **Engine 2, JIT** (later, own ticket when phase starts): same AST
   through the in-tree backend (asmcore/obj writer) -> native fn ptr cached
   in the word body. Env types are concrete at block-compile time, so
   attribute access compiles to fixed-offset loads. Forth-native shape:
   native words ARE compiled words.

## Language / porting plan (user policy 2026-07-19)

Start in PASCAL (avoids the chicken-egg on NilPy features; libs are
language-neutral per Track B). Port to NilPy once N is feature-complete
enough — the port is then itself an N corpus exercise. Same public surface
either way so consumers don't care.

Gate: standalone test suite driving the extracted 134-block corpus against
recorded CPython results (no uforth needed); make lib-test green.

## Track B note (2026-07-20 sweep)

Blocked-by edge added for [[feature-rtti-field-reflection]], which the ticket's
own header lists as a dependency ("Depends on feature-rtti-field-reflection for
the host bridge") — the tree-walker resolves `vm.here` / `vm.memory[i]` /
`push(x)` through field and method RTTI, so there is no engine without it.

Also worth flagging for whoever ranks this: it is a **large** umbrella (a
tokenizer + parser + AST cache, then a tree-walking engine, then a JIT), not a
single slice. The one piece that is genuinely startable today and independent of
the RTTI dependency is extracting uforth's 134 PYTHON blocks with their CPython
results into a fixture corpus under `test/` — that is worth doing on its own,
because it pins the contract before any engine exists to argue with.

