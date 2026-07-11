---
prio: 45
---

# complex numbers the FPC way: global operator overloading + ucomplex unit

- **Type:** feature (Pascal frontend + library) — Track P (operator
  overloading, the real work) + Track B (the ucomplex unit, trivial once P
  lands)
- **Status:** backlog — filed 2026-07-11 (user: "worth a ticket of itself",
  out of the ISO-10206 discussion in [[feature-pascal-otherwise-case-keyword]])
- **Owner:** —

## How FPC does it (verified on stock FPC 3.2.2, 2026-07-11)

NOT a builtin type. `ucomplex` unit (rtl-extra), plain record + GLOBAL
operator overloads:

```pascal
type complex = record re, im: real; end;
const i: complex = (re: 0.0; im: 1.0);
operator := (r: real) z: complex;             { implicit real -> complex }
operator + (z1, z2: complex) z: complex;      { +, -, *, /, = ; also
                                                complex<->real mixed forms }
function cinit(re, im: real): complex;
{ cmod, carg, csqrt, cexp, cln, csin, ccos, ctan, conjugate, ... }
```

Usage compiles and runs today with fpc, zero directives:
`c := a * b + a;` → `14.00 2.00` for a=3+4i, b=1-2i; `csqrt(-1)` → i.

(Extended Pascal ISO 10206 instead made `complex` a builtin simple-type with
`cmplx(re,im)`, `polar(r,theta)`, `re()/im()/arg()` and `**`. FPC ignored
that; nobody targets it. We follow FPC.)

## Plan — two rungs

1. **Track P: global operator overloading** — the actual feature.
   `operator <op> (args) resultname : type; <body>` at unit/program level.
   Needed ops for ucomplex: `+ - * / = :=` (`:=` = implicit conversion, is
   what makes `z := 1.5` and mixed real/complex arithmetic work). Frontend
   sugar: each declaration is a normal function under a mangled name keyed
   on (op, operand type kinds); binop resolution over record operands looks
   up the overload before erroring; assignment/argument-passing consults
   `:=` overloads for conversion. Records already pass/return by value, so
   NO new IR — if that holds, this stays pure Track P; anything needing a
   new IR op → Track A ticket per the rules.
   The `operator` keyword is already recognized as a member prefix
   (parser.inc ~944, class operators unparsed) — this ticket is the
   *global* form; the tforin2/5/24 skips (named/class operators
   Initialize/Finalize/Explicit) are adjacent but NOT in scope.
2. **Track B: `lib/rtl/ucomplex.pas`** — port FPC's unit (record, consts,
   the operator set, cinit/cmod/carg/conjugate, csqrt/cexp/cln/trig).
   API-compatible with FPC so user code moves over unchanged. Golden test
   vs FPC-computed values (the FP-determinism rules apply: exact expected
   strings, watch libm divergence — use own-RTL math per
   [[project_rtl_sqrt_correctly_rounded]] precedent).

## Payoff

- The user's actual want from the whole ISO discussion: complex arithmetic.
- Operator overloading is the enabling feature and pays rent far beyond
  complex (vectors, matrices, bignum, the fgl/collections story) and is a
  chunk of FPC-compat on its own (several skiplisted conformance tests).

## Gate

P rung: `make test` + self-host fixedpoint byte-identical (shared
parser.inc = A-gated), negative tests (unknown operator, ambiguous
overload). B rung: `make lib-test` with the golden ucomplex test.
