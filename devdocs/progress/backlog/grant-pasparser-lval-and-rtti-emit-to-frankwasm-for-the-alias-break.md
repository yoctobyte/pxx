---
slug: grant-pasparser-lval-and-rtti-emit-to-frankwasm-for-the-alias-break
title: "GRANT: pasparser_lval.inc + rtti_emit.inc to frankwasm (A+P), for the WideString alias break"
track: A+P
prio: 50
type: grant
status: backlog
owner: "frankwasm"
created: 2026-08-30
found-by: frank-coordinator
summary: "frankwasm holds compiler/defs.inc, compiler/pasparser_lval.inc and compiler/rtti_emit.inc for feature-unicodestring-model. symtab.inc is QUEUED behind frank-optimize. DO NOT CLAIM these files — this ticket is a lock record, not work."
---

# The grant

**DO NOT CLAIM.** This is a lock record. It exists because a grant is a lock the ranker
cannot see (`bug-t-a-grant-is-a-lock-the-ranker-cannot-see`), and an unfiled grant is one
that only lives in a message nobody else can read.

Given 2026-08-30 by the coordinator to **frankwasm**, for `feature-unicodestring-model`:

| file | lane | status |
| --- | --- | --- |
| `compiler/defs.inc` | A | **held** — `tyWideString` landed at ordinal 32 (later DELETED under option B) |
| `compiler/pasparser_lval.inc` | P | **held** — the alias break, two resolvers at ~:6322 and ~:6424 |
| `compiler/rtti_emit.inc` | A | **held** — the RTTI kind list, ~:942 |
| `compiler/symtab.inc` | A | **QUEUED** behind frank-optimize — TypeSize ~2922, ordinal-ness ~3120, name table ~8949 |
| `compiler/ir.inc` | A | **held** — the `:1794` index-stride site |
| `compiler/ast_arena.inc` | A | **held** (added ~14:2x) — the AST node element slot |
| `compiler/pasparser_decl.inc` | P | **held** (added ~14:2x) — the record-field element slot |

## Why A+P is safe here, checked rather than assumed

`working/` holds only frankwasm's own ticket. `pasparser_lval.inc` was last touched
2026-08-29 by `121aecee2`, landed and unrelated. frankA is the only other agent in the
P carve-out and is in `pasparser_proc.inc`, disjoint from `_lval`.

**Neither holds `lexer.inc`** — that is the file whose sharing makes "P + anything" the
hazard CLAUDE.md warns about, and the combination is only safe while that stays true.
If either agent finds it needs `lexer.inc`, it stops and asks; it does not take it.

## The correction that produced this grant

The coordinator's original file list was `defs.inc` + `symtab.inc` and **could not have
worked**. frankwasm caught it before editing:

> `symtab.inc` makes a `tyWideString` **well-formed**; `pasparser_lval` is what makes one
> **exist**.

The alias lives in two name->kind resolvers that map `widestring` and `unicodestring` to
`tyAnsiString`. Without that file nothing ever constructs the kind and every symtab case
is unreachable — the type would have been landed, well-formed, and unnameable by any
program.

## The gate the holder must answer for

Both resolver sites are guarded by `PasDefineExists('PXX_MANAGED_STRING')`, so `widestring`
resolves to `tyAnsiString` **or** `tyString` depending on the build. **The acceptance test
must name which arm it ran under, and run both** — otherwise the alias breaks in one
configuration and silently persists in the other, and the tested arm's verdict is
inherited by an arm nobody measured. Same class as the native-green repro that closed a
bug live on four other targets (`bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets`).

sysutils' `WideString`/`UnicodeString` identity functions are *documented* as the identity;
at the moment the alias breaks that documentation becomes wrong rather than stale. Change
them in the same commit.

## Release

Coordinator releases on frankwasm's word, or when `feature-unicodestring-model` resolves.


---

## ADDENDUM ~14:2x — two more files, and the ordering constraint GREW

Granted `ast_arena.inc` and `pasparser_decl.inc`. Both verified free by enumeration, not
inference: no open grant names either, `working/` holds only the cdecl, unicodestring and
xtensa-ruling tickets, and the P-lane neighbour (frankA) is in `pasparser_proc.inc`,
disjoint from `_decl`.

### Why they are needed — `ir.inc:1794` derives its type from THREE entities

| arm | width slot |
| --- | --- |
| `AN_IDENT` → `Syms[].TypeKind` + **`ElemType`** | **exists**, done — real sha `100d68f51` |
| `AN_FIELD` → `RecFieldType(...)` | none — fields carry `UFldTk`/`UFldPtrElemTk`, no string element |
| else → `ASTTk[baseNode]` | none — no AST node carries one |

So `rec.w[i]` and `(a + b)[i]` would index a wide string at **stride 1, silently**. The
second is load-bearing for the whole ticket: `WideChar(u1) + WideChar(u2)` is an
*expression*, so the AST-node slot is what the wall actually needs.

### THE ORDERING CONSTRAINT — a constraint, with its reason, not a plan

```
1. ir.inc:1794 symbol arm                      DONE (100d68f51)
2. AST node element slot                       ast_arena.inc
3. record-field element slot                   pasparser_decl.inc
4. the six per-backend COW guards              six ir_codegen*.inc — coordinator-sequenced
5. Length (frontend shift)
---- only then ----
6. break the alias + fix sysutils, ONE commit
```

**The alias break is the only thing that can construct a wide string.** Until it lands,
every gap above is unreachable *and untestable* — so shipping the alias with any of 2-5
missing opens a window that **nothing can detect**, because no test can build a wide string
to find it. A hazard that can be neither triggered nor observed is one that survives.

That is why the order is a constraint rather than a preference, and why it must not be
innocently reordered by a later reader.

### Step 2 added ZERO new mechanisms, and that is the finding

frankwasm checked for an existing slot before adding one, and found `symtab.inc:4169`:

```pascal
Syms[SymCount].ElemType := tyInteger;
if tk = tyAnsiString then
  Syms[SymCount].ElemType := tyChar;
```

A managed string symbol **already records its element type** — an explicit special-case at
the `AllocVar` chokepoint, not an accident. Confirmed with `a.symptr`: `s: AnsiString` shows
`kind=23 elemType=3`. No parallel array, no resolver. `ResolveNodeRec` was rejected as a
template for the same reason — it is a structural walk whose own comments call it *"a
recurring landmine"* and which grew arms one bug at a time.

Verified behaviourally rather than argued inert: string iteration, copy-on-write
(`s[1] := 'H'`), a record string field and an indexed concat result all match fpc 3.2.2, plus
both regressions green.

---

## SHA HYGIENE, ~15:1x — every sha this grant originally cited was rewritten

`tools/sync.sh` rebases on nearly every push here, so a sha read from `git log` **before**
the push names a commit that survives only in the author's reflog. frankwasm reported five
such rewrites in its own ticket and in two messages to the coordinator; this grant had
inherited one of them.

That is `bug-t-resolve-cites-a-sha-the-rebase-then-rewrites`, which CLAUDE.md documents and
which three parties then walked into on the same campaign in one afternoon — the author, the
ticket, and the coordinator relaying it onward. **The documentation was not the problem; the
habit of quoting a number you can see is.**

Working rule, same shape as `resolve` taking no sha: **cite a sha only after `git log
origin/master` shows it**, or cite nothing and let `sync.sh` fill it in. A relayed sha is
worse than an unrelayed one, because the recipient has no way to know it was read pre-push.

## Amendment 2026-08-30 (late): `pasparser_proc.inc` GRANTED, `ir.inc` LENT OUT

**GRANTED to frankwasm, effective now: `compiler/pasparser_proc.inc`.**

6c-params is *entirely* in that file — every param staging array, both
Self-insertion shifts and the durable stores — and it was not in the original
list. frankwasm asked before touching it rather than discovering the collision in
a rebase.

**It is free to grant:** frankC held it for the p30 diagnostic fix
(`4794d1251`, threading `diagLine`/`diagSpell` through `ParseUsesUnitBody`), and
that landed and pushed before this grant. frankC is on `cparser.inc`/`cir.inc`.
frank-rust holds `pasparser_generic.inc`, which is a different file.

**LENT to frankC, narrowly and temporarily: three regions of `compiler/ir.inc`.**

```
ir.inc:686,687   IRLowerBitFieldRead / ...Store  — the forward decls
ir.inc:7076      call site
ir.inc:10161     IRLowerBitFieldStore call
ir.inc:10162     IRLowerBitFieldRead call        — a SECOND call site, unlisted in the original ask
```

**CORRECTED.** frankC's original spans (`686 / 7040 / 10117`) were read from a
tree predating frankwasm's 6b, item-5 and corruption-fix commits, and are stale
by 36-45 lines. **`10117` in the current tree is `UFldStrCap` / `FrozenStrSlotSize`
— frankwasm's own campaign territory** — so a patch applied at literal line
numbers would land in the wrong place *with no conflict marker to warn anyone*.
And there are **two** call sites in the 10161 region, not one: if the fix changes
the signature, both need it.

**Re-locate by symbol, never by line:** `git pull --rebase` then
`grep -n IRLowerBitField compiler/ir.inc`. The 10161 neighbourhood sits inside the
`AN_ASSIGN` arm of `IRLowerAST`, which frankwasm edited today (`6e25bdcde`, the
record-field `array[..] of string[N]` overrun) — landed and pushed, so it arrives
by rebase, but it is precisely the case where a stale line number does damage
quietly.

Nothing else in the file. Bitfield-layout work only
([[bug-c-a-long-long-bitfield-after-a-smaller-one-puts-later-members-at-the-wrong-offset]]).
frankwasm read its own working set and confirmed **6c-params does not open
`ir.inc` at all** — a param inside its own callee body resolves through the
existing `AN_IDENT` arm, and the caller-side read is in `symtab.inc`'s overload
matching. Only 6c-**returns** needs the file (~6 lines, one new `AN_CALL` arm in
`ASTStrElemTkOf` reading `ProcRetStrElemTk`).

**`ir.inc` returns to frankwasm when frankC lands the bitfield.** The rest of the
grant is unchanged and stays whole.

### The count that was wrong, and it was wrong in both halves

frankwasm reported 6c as "~72 references across two files" and corrected it
unprompted: **72 was a raw grep over the pointer family including doc comments
and prose** — `ProcRetPtrElemTk` alone contributes 37 refs, roughly a dozen of
them commentary. Read-verified, 6c is **~25 real edit sites across FIVE files**.

Both halves of the original number were wrong, and the file-count half is the one
that mattered: it is what made the missing `pasparser_proc.inc` grant invisible
to both of us. Same error the coordinator made twice today, in the other
direction — **inferring a working set from what the change is about instead of
from where it has to happen.**
