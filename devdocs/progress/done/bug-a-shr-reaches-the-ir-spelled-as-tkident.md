---
slug: bug-a-shr-reaches-the-ir-spelled-as-tkident
title: "`shr` reaches the IR spelled Ord(tkIdent), and each consumer has to know that separately"
track: A
prio: 60
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-28
summary: "DONE 2026-08-31 as a RENAME (314481dd7): the IR's logical shift-right is now Ord(tkShrLogical) — appended at the tail of TTokenKind — instead of Ord(tkIdent), across 25 sites. NOT the merge onto Ord(tkShr) this ticket originally prescribed: tkShr is the ARITHMETIC shr (C `>>` on a signed operand) and the merge was measured to turn test_shr_width rows 1-3 into -4, unsigned row included. Acceptance was byte-identity of emitted output on seven targets at -O0..-O4. Two predicted failures had already fired: ASTConstIntValue declined every shr (fixed 5b12e6a5e), and IRValidate admitted the operator only because Ord(tkIdent) is 1. Left open deliberately: the wasm32 fold (that backend's own missing shr_s, not a duplicate) and the variant runtime's third vocabulary."
---

# The shape

`compiler/ir.inc:9507` says it plainly:

```
{ Pascal spells `shr` as an IDENTIFIER — there is no tkShr token for it }
...
if item = Ord(tkIdent) then item := Ord(tkShr);     { :9518 at HEAD }
```

That substitution is correct and local. The problem is that it is local: the
token that reaches `IR_BINOP`'s operator field is still `Ord(tkIdent)`, so the
normalisation is a property of one reader rather than of the IR.

# Why it is worth a ticket rather than a shrug

`devdocs/dev/normalise-dont-special-case.md`: when a construct is reachable
through two shapes, normalise rather than growing a second path, *because the
second path is the one that stays broken*. There is now a second path. The
wasm32 backend (branch `wasm`, `compiler/ir_codegen_wasm32.inc`) repeats the
substitution with a comment pointing here.

The failure mode for a consumer that does not know is worse than a missing
feature: `tkIdent` is not an unlikely value that would obviously fall through to
an "unsupported operator" arm. It is token 1. Any consumer that dispatches on a
small operator ordinal, or that treats an unrecognised operator as a default,
can quietly do the wrong thing for every `shr` in the program.

# Fix

Substitute at the point the `IR_BINOP` node is appended, so the IR carries
`Ord(tkShr)` and no consumer has to know the lexer's accident. Then delete the
substitution at ir.inc:8878 and the one in ir_codegen_wasm32.inc, and grep for
others — per the doc's own rule, fixing one arm of a double case means checking
the sibling before closing.

Genuinely low prio: nothing is wrong today, both current consumers handle it.
The value is that the next one cannot get it wrong, and the fix deletes code
rather than adding it.

# Found

By the wasm32 backend, 2026-08-28: `shr` showed up in the coverage report as
`binary operator 1`, which is how the lexer accident became visible at all.

---

## 2026-08-31 — corrected, and repriced 20 → 60 (owner)

**The premise sentence was half wrong, in the direction that understates it.**
This ticket said *"there is no `tkShr` token for it"*. `tkShr` **exists**, and
`compiler/clexer.inc:871` produces it correctly:

```pascal
begin Inc(SrcPos); CurTok.Kind := tkShrEq; end
else CurTok.Kind := tkShr;
```

So this is not "a token we never minted". It is **one IR operator field meaning
two different things depending on which frontend built the node** — `Ord(tkShr)`
from C, `Ord(tkIdent)` from Pascal — read by 25 `tkShr` sites across the
compiler. A consumer that handles `Ord(tkShr)` is *correct for C code and
silently wrong for Pascal code*, in the same binary, at the same site. That is a
strictly stronger statement of the bug than "each consumer has to know
separately", and it is the reason the fix is normalisation rather than tidying.

Line numbers refreshed: the substitution is at `ir.inc:9518` (was cited as
:8878) and the comment at `:9507` (was :8867). Still live at HEAD; the wasm32
second arm is still at `ir_codegen_wasm32.inc:1276`.

**Why the reprice, and it is a ranking finding, not a judgement about this
bug.** `shr` has produced **ten** tickets. Eight are closed, individually,
between 2026-06-26 and 2026-08-25, priced 30-60:

```
bug-cardinal-expr-promotion-shr-orphan            bug-a-strict-fpc-shr-by-zero-drops-the-sign
bug-const-expr-shl-shr-not-folded                 bug-a-unary-minus-binds-looser-than-and-shr
bug-shr-signed-integer-width                      bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc
bug-a-promoint-shr-yields-nothing-...             bug-a-variant-shr-is-arithmetic-where-static-shr-is-logical
```

This ticket — upstream of that family — sat at **20**, the lowest prio of all
ten. That is not a mistake anyone made. **Prio propagates only down declared
`blocked-by:` edges, and seven of the eight symptoms were filed BEFORE this
ticket existed, so they could never have declared one.** The ranker reads one
ticket at a time and has no way to see the shape of a pile. Tooling follow-up:
`feature-t-detect-ticket-clusters-that-share-a-construct`.


---

## 2026-08-31 — the prescribed fix is a MISCOMPILE, and the first live symptom is fixed (frankC)

**Do not perform the `# Fix` section as written.** Substituting `Ord(tkShr)`
for `Ord(tkIdent)` at IRAppend sends Pascal's `shr` to the arm that emits
`sar`. Measured at HEAD: the backends distinguish logical from arithmetic
right-shift by exactly these two ordinals, and the C frontend already relies on
it —

```pascal
{ cparser.inc, CMakeBinop }
if TypeSigned(IntToTypeKind(ASTTk[l])) then ivalOp := Ord(tkShr)   { arithmetic }
else                                       ivalOp := Ord(tkIdent); { logical    }
```

```pascal
{ ir_codegen386.inc:1212 and its four siblings }
else if (op = Ord(tkShr)) and signedOp then ... sar
```

So `i shr 1` for `i: Integer = -8` would answer **-4** instead of the logical
value, on x86-64, i386, arm32, aarch64 and riscv32 at once. That is
`bug-c-signed-arith-shift-right` run backwards — the same collision, from the
other side.

### The premise, corrected once more — and this direction OVERSTATES it

The 2026-08-31 note says the field "means two different things depending on
which frontend built the node". It does not. It means **one** thing, and both
frontends already agree on it:

| ordinal | means | written by |
| --- | --- | --- |
| `Ord(tkIdent)` = 1 | logical shr | Pascal `shr`; C `>>` on an **unsigned** operand |
| `Ord(tkShr)` = 119 | arithmetic shr | C `>>` on a **signed** operand only |

C normalises at `CMakeBinop`, at the frontend boundary, which is the right
place. The IR is *already* normalised. What is wrong is only the **spelling**:
the logical-shr opcode is spelled with a name that says "identifier".

That distinction is the whole ticket. "Two meanings, one field" invites a merge,
and the merge is the miscompile above. "One meaning, a lying name" invites a
rename, which is safe and is what this needs.

### The count that says it is a design flaw, not a wart

`root-cause-over-microfix.md`: two mechanisms for one concept is a smell, three
is a design flaw. There are **three**, and the third is not in this ticket:

| ordinal | static backends | variant runtime (`VarBitwiseInt`, builtinheap.pas:4702) |
| --- | --- | --- |
| `Ord(tkIdent)` = 1 | logical | — |
| `Ord(tkShr)` = 119 | **arithmetic** | **arithmetic** (NilPy `>>`) |
| `1119` | — | **logical** (Pascal, via `PXXVarBinOpPas`) |

`ir.inc:9518`'s `if item = Ord(tkIdent) then item := Ord(tkShr)` maps *logical*
onto the ordinal that means *arithmetic* in the static vocabulary. It is correct
only because `PXXVarBinOpPas` rewrites 119 back to 1119 for Pascal — two
rewrites that cancel, in different files, one of them in the runtime, which
`builtinheap.pas:4679` notes "is not a token: it is the out-of-band opcode". A
reader who finds either rewrite alone will draw the wrong conclusion, which is
how the `# Fix` above got written.

### The live symptom — this ticket is no longer "nothing is wrong today"

Measured 2026-08-31, and fixed in `5b12e6a5e`:

```pascal
writeln(IntToHex(-(256 shr 4), 8));   { pxx FFFFFFFFFFFFFFF0, fpc FFFFFFF0 }
writeln(IntToHex(-(256 shl 1), 8));   { FFFFFE00 — correct, both }
```

`ASTConstIntValue` (`pasparser_stmt.inc`) had arms for `tkShl` and `tkShr` and
none for `tkIdent`, so it fell to `else Result := False` for every Pascal `shr`
and the enclosing constant did not fold. Its two callers are the ones that type
a folded constant the way FPC does — smallest signed type that holds it — so the
unfolded operand was typed `Int64` and bound the `Int64` `IntToHex` overload.

That is a **third** consumer, and it was neither of the two this ticket says
"handle it". It failed in precisely the way the ticket predicts — dispatching on
a small ordinal and defaulting — which is the argument for the rename, made by
the code rather than by the doc. `test/test_shr_const_fold_typing.pas` guards it,
with the `shl` and plain-constant controls that made it legible.

### What is actually left, and it is a rename

Add a distinct ordinal for logical shr — appended at the END of `TTokenKind`, so
no existing ordinal moves and no emitted byte changes — and replace the ~25
`Ord(tkIdent)` shift sites with it. Reference list, from HEAD:

```
ir_codegen.inc:3079,6940,7176   ir_codegen386.inc:1171,1184,2745
ir_codegen_aarch64.inc:1649,2743  ir_codegen_arm32.inc:702,713,2198
ir_codegen_riscv32.inc:845,851,2395  ir_codegen_xtensa.inc:969,2370
ir_codegen_wasm32.inc:1289      ir.inc:1421,4854,9518   cir.inc:86
cparser.inc:959   pasparser_expr.inc:9115   pasparser_call.inc:134
pasparser_stmt.inc (the arm added by 5b12e6a5e)   pyparser.inc:43532
```

The substitution point is `IRAppend`, conditioned on `kind = IR_BINOP` — the
`c` field is an operator only there, and a blanket rewrite would corrupt every
other node whose `c` happens to be 1.

**Acceptance is byte-identity, not a green suite.** A pure rename must leave
every emitted binary unchanged on every target; anything else means an ordinal
moved. That is a positive control the change carries for free, and it is
stronger than any test in the tree.

Not attempted in this session: the two live wrongs above were worth more than
the rename, and a 25-site cross-backend rename deserves its own gate run rather
than the tail of someone else's.

## 2026-08-31 — done as a RENAME, with byte-identity as the acceptance test (frankC)

`tkShrLogical`, appended at the tail of `TTokenKind` so no existing ordinal
moves. `ParseTerm` renames on the way in — once, at the parser boundary, where
the loop condition has already established that this `tkIdent` is `shr` and
nothing else — and all 25 downstream sites read the new name. `314481dd7`.

**The merge was measured, not argued.** Building `op := tkShr` instead and
running `test_shr_width.pas`:

```
row 1  i shr 1     (Integer -8)   9223372036854775804  ->  -4
row 2  c shr 1     (Cardinal)              2147483644  ->  -4
row 3  q shr 1     (Int64 -8)     9223372036854775804  ->  -4
```

Row 2 is the one that settles it: an UNSIGNED operand, where no reading of any
dialect makes -4 right. And the self-host fixedpoint **converged cleanly in 2
rounds** under that miscompile — `compiler.pas` shifts nothing negative — which
is CLAUDE.md's "the fixedpoint cannot see a construct the compiler never writes"
earning itself a fourth time.

**Acceptance was byte-identity of emitted output**, against a compiler built
from the parent commit: shift, set, bitfield, C-shift and demo inputs, on
x86-64 / i386 / arm32 / aarch64 / riscv32 / wasm32 / xtensa-bare, at -O0..-O4
and under `--strict-fpc`. The three renamed paths byte-identity cannot reach
were checked by OUTPUT instead: `operator shr` overloading (the overload key and
`ASTIVal` must move together, and `test_operator_unary_and_keyword_forms.pas`
covers it), Variant `shr`, and NilPy `>>`.

Both predicted failures had already fired by the time the rename landed:
`ASTConstIntValue` declined every `shr` for two months (`5b12e6a5e`), and
`IRValidate`'s binop range check admitted the operator only because
`Ord(tkIdent)` is 1 — it now has to name `tkShrLogical` explicitly, which is
that check doing its job on this operator for the first time.

### What is deliberately NOT closed with it

The `wasm32` fold survives, and it is no longer a second arm of anything: that
backend has one right-shift instruction per width because it does not implement
C's signed `>>` yet, so it folds `tkShr` onto `shr_u` **by its own gap**. The
comment now says that, and names the line to delete (`shr_s` for `tkShr`) when
the gap closes. That is Track A/wasm work, not this ticket.

The **third vocabulary is untouched and stays that way**: the variant runtime,
where 119 is arithmetic and out-of-band 1119 is logical, reached through two
cancelling rewrites in two files. Unifying it means changing an opcode the
RUNTIME hardcodes because it cannot see `defs.inc` — a different job with a
different blast radius, and no symptom asks for it today. `ir.inc`'s rewrite now
states the cancellation out loud so the next reader does not simplify one half.

## Log
- 2026-08-31 — resolved, commit bae0b7e34.
