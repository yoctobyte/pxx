---
track: A
prio: 30
type: refactor
blocked-by: []
summary: "`not` decides bitwise-vs-logical from a WHITELIST of operand node kinds whose type is 'authoritative', because the frontend mistags some logically-Boolean expressions as tyInteger and self-host depends on those staying logical. The list has grown one entry per bug report — array element, field, deref, Ord(x), value-cast, nested not, and/or/xor at explicit width, and now AN_NEG — and every entry arrived AFTER someone shipped wrong bits. Fix the mistagging instead, then believe ASTTk."
owner: claude-A
---

# `not` should trust the operand's type, not a list of node kinds

- **Type:** refactor (removes a class of bugs rather than one) — Track A
  (`compiler/pasparser_expr.inc`, and wherever Boolean expressions get tagged
  `tyInteger`).
- **Status:** done
- **Opened:** 2026-08-21, closing
  `bug-a-not-of-a-negated-operand-is-a-boolean-not`.

## The shape

Pascal spells bitwise complement and logical negation with one word, so `not`
must pick from the operand. The obvious rule — "integer operand → bitwise,
Boolean operand → logical" — is not usable today, because the frontend tags some
expressions that are *logically Boolean* with `tyInteger`. `compiler.pas` itself
contains `not (a = b)` and `not Eat(...)` carrying `ASTTk = tyInteger`, and
trusting those flips them to `xor rax, 1`-vs-`not rax` the wrong way and breaks
the self-host fixedpoint.

So the code instead asks "is this operand node kind one whose type I believe?"
and consults a whitelist. Read `git log` on that condition and it is a museum:

| entry | arrived with |
| --- | --- |
| array element, field, deref | `not arr[i]` / `not rec.f` produced garbage masks |
| `Ord(x)` | `bug-pascal-not-of-ord-uses-boolean-negation` |
| ordinal value-cast | `not Int64(0)` printed TRUE |
| nested `not` | `not(not(q))` flipped the outer to boolean |
| `and`/`or`/`xor` at explicit width | `not (q3 or q4)` on qwords |
| arithmetic `AN_BINOP` | `not (x shr 1)` |
| `AN_NEG` | `not -1` printed TRUE (2026-08-21) |

Every one of those is the same bug, and every one was found by a user or a
differential rather than by the compiler. A whitelist of the shapes someone
happened to hit is not a rule; the next shape is already wrong and nobody knows
which it is.

## What to do instead

1. **Find the mistagging.** Enumerate where a Boolean-valued expression ends up
   with `ASTTk = tyInteger` — comparisons and logical `and`/`or`/`xor` are the
   named suspects. `PXXDBG` can print the inferred tag rather than reasoning
   about it (`devdocs/dev/debugging-playbook.md`: measure, do not reason).
2. **Fix the tags** so a Boolean expression is `tyBoolean`.
3. **Delete the whitelist** and drive `not` off `ASTTk` alone.

The self-host fixedpoint is the gate and the risk in one: `compiler.pas` relies
on the current behaviour of `not (a or b)` and `not (r and v)`, so step 2 must
land those as `tyBoolean` before step 3 can be believed. Doing 3 without 2 is
what the existing comment warns hung a self-compile once already.

## Why it is prio 30 and not higher

Nothing is known-broken today — the whitelist covers every shape anyone has
tried. This buys the *absence* of the next report, which is real but not urgent,
and it touches type inference under a byte-identical gate. Take it when there is
room to measure, not between two bug fixes.

## Resolved 2026-08-24 (claude-A) — the premise had expired; only step 3 was left

The ticket's plan is three steps: find the mistagging, fix the tags, then delete
the whitelist. **Steps 1 and 2 were already done** — by other work, at some point
after this was filed — and the ticket's warning that *"doing 3 without 2 is what
hung a self-compile once already"* was guarding a condition that no longer
holds. Measured first, exactly as the ticket asks
(`devdocs/dev/debugging-playbook.md`: measure, do not reason).

### Step 1, measured rather than reasoned

`PXXDBG=a.ast` on the four expressions the ticket names as mistagged:

```
not (a = b)      binop tk=2   (tyBoolean)
not Eat          call  tk=2
not (p and q)    binop tk=2
not (p or q)     binop tk=2
```

All four are `tyBoolean`. The claim in the code comment — *"`not (a = b)`,
`not Eat(...)` appear in compiler.pas with ASTTk = tyInteger"* — was true when it
was written and is not true now.

### Step 3, and the evidence that it changes nothing

`bitNot` is now `(ASTTk = tyInteger) or (ASTTk in tyInt8..tyNativeUInt)`. The
whole node-kind list is gone, along with `opIsArith`/`notOp`.

**Safe by construction, and worth stating in this direction:** the old condition
was `integer-typed AND whitelisted`. Removing the second conjunct can only turn
LOGICAL into BITWISE, never the reverse. The only way it can break is an
integer-TAGGED operand that is logically Boolean — which is exactly what the
measurement below rules out.

1. **Self-host fixedpoint converges in one round.**
2. **The compiler WITH the list and the compiler WITHOUT it emit a
   byte-identical `compiler.pas`** — the largest and most `not`-dense program in
   the repo — and byte-identical binaries for
   `test_bitwise_not_lvalue_b280.pas`, `test_const_bitwise_shift.pas` and
   `cbitnot_b11.c`. This is the decisive one: it is not "the tests still pass",
   it is "no emitted byte moved".
3. **A 53-expression `not` differential against fpc 3.2.2** — every operand
   shape the list ever named, plus comparisons, boolean ops, qword and/or/xor,
   `Ord`, casts, calls, derefs, array elements, nested `not` in both flavours —
   gives **identical results before and after**: one divergence in both runs,
   `not LongWord(4)` (fpc `-5`, pxx `4294967291`), which is a `WriteLn`-of-
   Cardinal signedness question and has nothing to do with `not`.
4. The compiler is **3,050 bytes smaller** (9,285,742 → 9,282,692).

### Test

`test/test_not_operand_type_matrix.pas` + `.expected` (fpc 3.2.2's own output),
35 rows: 19 integer operands that must come back as complements and 16 Boolean
ones that must come back as flips, covering every whitelist entry and every
shape it distrusted. Byte-identical to FPC natively and under qemu on
**i386 / aarch64 / arm32 / riscv32**.

`pinned` also passes it, and that is the point rather than a weakness: the
whitelist did cover every shape anyone had tried. The test's job is to stop the
list growing back, and to make the next mis-tag fail loudly here instead of in
someone's hash function.

### The rule left in the code

A comment where the list was, saying: **do not re-add a node-kind arm. If a
shape is wrong, the TAG is wrong; fix the tag.**

### Gate

`make compiler/pascal26` fixedpoint converged in one round; the byte-identical
A/B compile of `compiler.pas` and three bitwise tests; the 53-expression
differential; the new test on five targets; `tools/gate.sh quick` GREEN.

## Log
- 2026-08-24 — resolved, commit PENDING-COMMIT.
