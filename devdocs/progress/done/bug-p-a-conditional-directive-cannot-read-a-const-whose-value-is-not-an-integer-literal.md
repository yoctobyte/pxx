---
slug: bug-p-a-conditional-directive-cannot-read-a-const-whose-value-is-not-an-integer-literal
title: "`{$if}` cannot read a `const` whose value is a set or a folded call"
track: P
prio: 35
type: bug
status: done
owner: frankH
found-by: frankH
created: 2026-09-09
tags: [conditional-directives, lexer, fpc-corpus]
blocked-by: []
summary: "FIXED, and it was TWO defects plus a fourth hop nobody had traced. (1) pxx did not SHORT-CIRCUIT `and` in a `{$if}`, so FPC's portable `declared(X) and (X<>Y)` idiom was refused outright -- a shunting-yard applies the parenthesised `<>` before the `and`. Fixed by DEFERRING that error, so the genuine absent-define diagnostic stays byte-identical; left-only, and fpc refuses the right-only form too (measured, pinned). (2) The const door now reads a const naming another CONST across units, `high()`/`low()` as a const value, and the DISTINCT-TYPE alias form `NAME = type X;` -- four hops, which is what FPC rgobj.pas:1728 actually needs, since the LEFT operand chains as well. No new table and no new evaluator: it reuses OrdinalNameToTk + OrdinalTypeBound and PasCondTypeAlias. 12 fixture rows byte-identical to fpc 3.2.2, plus 3 must-refuse controls, one of them timeout-guarded because a const cycle fails by HANGING. rgobj CLEARS this wall and stops at TExecuteFlags; nld/ncnv are shape 1, split out as bug-p-a-conditional-directive-cannot-evaluate-in-over-a-set-constant."
---

# `{$if}` over a const that is not an integer literal

The const door added by
[[bug-p-a-conditional-directive-cannot-read-a-constant-or-a-type-the-source-declares]]
matches `NAME = <integer literal> ;` and deliberately nothing else — that
ticket's own "what must NOT be widened" section says a name whose value is an
EXPRESSION should keep the current error rather than be guessed at. These are
the two expression shapes the corpus actually asks for, so they are the
evidence that would widen it.

- **Umbrella:** `umbrella-pxx-compiles-fpc-itself`

## The two shapes, with the FPC unit and line that produced each

**1. Set membership, 2 units (nld, ncnv).** `nld.pas:700`:

```pascal
{$if (cs_opt_use_load_modify_store in supported_optimizerswitches)}
```

`supported_optimizerswitches = genericlevel1optimizerswitches + ...`
(`x86_64/cpuinfo.pas:205`) — so answering it needs a set-valued constant
folded from three other set-valued constants, and then an `in`. pxx answers
`conditional directive: expected operator` at the `in`. **ncnv is the same
directive, not a second one**: ncnv's interface `uses nld`.

**2. A const whose value is a folded call, 1 unit (rgobj).** `rgobj.pas:1728`:

```pascal
{$if declared(RS_STACK_POINTER_REG) and (RS_STACK_POINTER_REG<>RS_INVALID)}
```

with `RS_INVALID = high(tsuperregister)` at `cgbase.pas:400`. pxx answers
``conditional directive: `RS_INVALID` has no integer value here``. This half is
the smaller of the two and shares its machinery with `ConstEvalOrdBound`, which
already folds `low`/`high`/`pred`/`succ` — the const walk is at TOKEN level and
has no type, which is the actual gap.

## What works already, so the boundary is exact

Measured at `fcbe280b7`, all byte-identical to fpc 3.2.2: an integer const in
this file or a used unit, a hex const, a negative const compared with `<`,
two source consts compared with each other, `sizeof` through a one- or two-hop
type alias in either file, `sizeof(pointer) > sizeof(TAlias)` and
`declared(X) and (X <> Y)` over integer consts. (`defined(X)` also answers, and
was checked against pxx only -- it is not one of the fpc-verified rows.) The fixture is
`test/test_p_a_conditional_directive_can_read_a_source_const.pas`.

## Why prio 35

Three units of 207, and both shapes are behind
[[bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface]]
anyway — no unit here compiles when this is fixed. It is filed so the corpus
row has an owner, not because it is next.

## 2026-09-11, frankH — shape 2 is TWO defects, and the one nobody had filed is fixed

Reducing shape 2 found a second, independent bug in front of it, and the ticket
as filed describes only the one behind.

`{$if declared(RS_STACK_POINTER_REG) and (RS_STACK_POINTER_REG<>RS_INVALID)}` is
FPC's portable idiom for *compare it only if it exists*, and it is written that
way **because `and` short-circuits**. pxx did not short-circuit: the evaluator is
a shunting-yard, the parenthesised `<>` is applied BEFORE the `and`, so the
comparison raised and no short-circuit could ever save it. A seven-line repro
with an undeclared name — no consts, no `high()`, nothing from shape 2 — already
reproduced, and fpc compiles it.

**FIXED (this commit).** The relational now DEFERS its error instead of raising:
the comparison yields a value-stack slot of a new kind carrying the exact message
it would have printed, `and`/`or` may discard it on a decided LEFT operand, and
one still standing at the top raises it verbatim. So the diagnostic that exists
for a genuine absent define is byte-identical, same wording, same named operand —
which matters, because that message was built deliberately in response to a
measured incident (`{$if FPC_FULLVERSION < 20701}`, 2026-09-05).

**Left-only, and that asymmetry is asserted rather than assumed.** `(X<>3) and
declared(X)` is False arithmetically, and **fpc refuses it — measured, not
predicted**, because fpc evaluates left to right. Two fixtures pin the refusals,
because a later widening to "either operand may settle it" would look like an
improvement and pass every other row in the tree.

### It moves no corpus unit, and here is the number that says so

`rgobj`, `nld`, `ncnv` re-measured at the fix, through
`tools/fpc_compiler_corpus_probe.sh`'s own invocation: **all three fail
identically to before.** The reason is specific and worth recording, because the
ticket's framing implies otherwise — **17 of FPC's 18 `cpubase` files DO declare
`RS_STACK_POINTER_REG`**, `x86_64/cpubase.inc:90` among them. So on the target
the probe uses, the left operand is TRUE, the right side genuinely must answer,
and shape 2 is still required. The short-circuit path is reached in this corpus
only for `x86/cpubase.pas`, which is not a target on its own.

That is this umbrella's own finding again, from the other side: the fix is
correct, oracle-verified, and worth zero units. Filed as fixed on its own merits
— real code that fpc compiles and pxx refused — not as corpus progress.

### What shape 2 still needs, now that it is the only thing left in this half

`RS_INVALID = high(tsuperregister)` (`cgbase.pas:400`) needs three pieces, each
following an existing precedent exactly:

1. `PasCondTypeAliasIn` accepts `NAME = <one token> ;` and `tsuperregister` is
   declared in FPC's **distinct-type** form, which is three tokens. Widening that
   walk to `NAME = type <one token> ;` is the first piece.
2. A name → ordinal **high bound** answer. `PasCondSizeOfTypeName` is the model
   and its comment is the constraint: it is forwarded from `compiler.pas`
   precisely so the answer stays beside `BuiltinTypeNameTk` rather than becoming
   a fourth name-to-width table. A bound table must arrive the same way.
3. `PasCondConstIntIn` accepting `NAME = high(<typename>) ;` and `low(...)`.

Shape 1 (`in` over a set const folded from three set consts) is bigger than all
of that together — a third value kind on the stack, set-union folding, and enum
member resolution — and should be split into its own ticket rather than carried
here.

## RESOLVED for shape 2 — four hops, and rgobj clears the wall

Shape 1 is split out as
[[bug-p-a-conditional-directive-cannot-evaluate-in-over-a-set-constant]], because
the two halves turned out to be work of very different sizes and one summary
could not be true about both.

Shape 2 needed **four** hops, not the one the ticket described — the left operand
chains too, which nobody had traced:

| hop | FPC source | what it needed |
| --- | --- | --- |
| `RS_STACK_POINTER_REG = RS_RSP` | x86_64/cpubase.inc:90 | a const naming another CONST, **across units** |
| `RS_RSP = $07` | x86/cpubase.pas:84 | (a literal at last) |
| `RS_INVALID = high(tsuperregister)` | cgbase.pas:400 | `high()` as a const value |
| `TSuperRegister = type word` | cgbase.pas:317 | the DISTINCT-TYPE alias form, four tokens |

**Nothing new had to learn how to evaluate anything.** Every piece reuses a walk
or a helper that already existed, which is why this stayed small:

- `PasCondOrdBoundOfTypeName` asks `OrdinalNameToTk` + `OrdinalTypeBound` — the
  same pair `TryConstHighLowValueInner` asks — so no range table was written into
  `paslexer.inc`. That is `PasCondSizeOfTypeName`'s rule, whose header records
  three separate fixes paid for having a second source of size truth.
- The const-to-const hop reuses `PasCondTypeAlias`. At token level
  `NAME = OTHER ;` is the same four tokens whether OTHER is a type or a const,
  and this walk has no section tracking **by design** — `PasCondDeclStartsAt`'s
  header records why a const/type section tracker is wrong on real source.
- Both new walks copy `PasCondSizeOfNameOrAlias` hop for hop, cap and all.

**The `A = B` refusal this ticket quoted was half right and is now half
retired**, said out loud rather than quietly contradicted: what it refuses is
GUESSING, and resolving `A = B` by looking B up is the resolution, not a guess.
`A = B + 1`, `A = 'x'` and the typed-const form still decline untouched.

### Measured

7 fixture rows byte-identical to fpc 3.2.2. `65535` is the value that cannot be
produced by a default, a size or a pointer width, and both directive rows are
asserted in **both** directions — an evaluator that resolved nothing answers
False and would agree with a one-directional test.

Declines re-checked and still loud, with no silent number: `high()` of an enum,
of a record, and a const cycle. The cycle has its own Makefile row **with a
timeout**, because its failure mode is a HANG, which no output assertion can
observe; it refuses in 0.00s at the hop cap.

**Corpus, through `tools/fpc_compiler_corpus_probe.sh`'s own invocation:**

| unit | before | after |
| --- | --- | --- |
| rgobj | `conditional directive: RS_INVALID has no integer value here` | **`unknown type: TExecuteFlags`** |
| nld | `conditional directive: expected operator` | unchanged — shape 1 |
| ncnv | `conditional directive: expected operator` | unchanged — same directive as nld |

rgobj **clears this wall** and stops at cfileutl.pas:136, which is the umbrella's
largest known wall (127 units,
[[feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags]]). It does not
compile, and saying so is the point: a wall cleared is a unit moved to the next
wall, which is this umbrella's own repeatedly-measured finding.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
