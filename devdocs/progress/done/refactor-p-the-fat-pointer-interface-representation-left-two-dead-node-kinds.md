---
slug: refactor-p-the-fat-pointer-interface-representation-left-two-dead-node-kinds
track: P
prio: 25
type: refactor
blocked-by: []
status: done
owner: frankH
found-by: frankD
created: 2026-09-09
summary: "DONE. AN_INTF_FROM_CLASS and IR_IMTADDR are retired -- both were residue of the 16-byte fat-pointer interface representation, which is now ONE WORD (the instance pointer, IMT recovered per call from RTTI by PXXIntfIMTOf). Nothing constructed either: AN_INTF_FROM_CLASS had zero references outside defs.inc, and IR_IMTADDR carried four backend encoder arms plus an IRVerify arm for a node nothing appended. 59 is now a HOLE in both namespaces and is deliberately NOT reused, so an old IR dump naming op 59 stays unresolvable rather than quietly meaning something else. The comment half landed first at 144e0ba26: ~35 comments across nine files, each read against its own path. Coordinated with frank-coordinator, who measured zero node-kind constants added to defs.inc in 2.6 days and supplied four whole-tree references a compiler/-scoped census could not see; all four updated here. iropname_lint 77 -> 76, clean."
---

# Residue of the fat-pointer interface representation

## What is dead, and the census that says so

    grep -rn AN_INTF_FROM_CLASS compiler/ | grep -v defs.inc   -> 0 lines
    grep -rn 'IRAppend(IR_IMTADDR' compiler/                   -> 0 lines

`AN_INTF_FROM_CLASS` (defs.inc) is an AST kind nothing allocates. `IR_IMTADDR`
is an IR node nothing appends, and it still has encoder arms in
`ir_codegen.inc`, `ir_codegen_aarch64.inc`, `ir_codegen_arm32.inc` and
`ir_codegen386.inc`, plus an `IRVerify` arm. Five arms for a node that cannot
occur.

`AN_INTF_CALL` is NOT in this set — 39 references, live, and
`pasparser_stmt.inc` states the current mechanism beside it ("recovers the IMT
per call via PXXIntfIMTOf").

## Why it is a ticket and not a commit

Removing an AST or IR node kind is **node numbering in `defs.inc`**, the one
thing CLAUDE.md says to coordinate by message. Both constants have therefore
been left in place and *marked* dead, each carrying the census command that
would retire it. Deleting them, and the five backend arms with them, needs the
message and cross-target gating that a four-backend edit implies.

## The comment drift, which is the expensive half

About a dozen comments in `ir.inc`'s lowering still describe the old
representation in live code:

- `build the CORBA fat pointer {IMT, instance} into the LHS`
- `interface := interface falls through to the 16-byte record copy below`
- `the address of its fat-pointer temp`
- `interface := nil — zero the whole fat pointer {nil, nil}`

They are describing code that moves one word. **This is not cosmetic — one of
these comments has already been read as a specification and cost a ticket.**
`bug-p-a-variant-cannot-hold-an-interface` was filed at prio 40 on
`pxx spells it tyRecord (a 16-byte fat pointer {IMT, instance})` taken from
`UClsIsInterface`'s own comment, and its design section prescribes widening the
variant payload from 8 bytes to 16 — work that is not needed, against a
representation that had already moved. It sat unclaimed from 2026-08-26 to
2026-09-09 with that blocker at the top of it.

Each of these needs its own path READ before rewriting, which is why they were
not corrected alongside the defs.inc ones: a comment rewritten from a
neighbour's measurement is exactly how this drift started. `defs.inc`'s
`UClsIsInterface` and `IMTClass` notes are corrected and say precisely what was
measured and what was merely read off a sibling.

## The measurement that settles any future version of this

    writeln(SizeOf(IIntf));   { 8, in pxx and in fpc 3.2.2 }


## 2026-09-09 (frankH) — DONE, both halves

Comment half: `144e0ba26`. Node half: this commit.

### The comment half was the expensive one, and three of them were not rewordings

~35 comments across nine files (`ir.inc`, `symtab.inc`, `pasparser_decl.inc`,
`pasparser_proc.inc`, `pasparser_expr.inc`, `pasparser_lval.inc`,
`pasparser_call.inc`, `pyparser.inc`, `builtinheap.pas`), each read against the
path it describes rather than against a neighbour's wording. Three were more
than stale prose:

- **`ir.inc`'s AN_INTF_CALL header** narrated `{IMT@0, instance@8}` and the line
  DIRECTLY BENEATH IT said "An interface value is ONE pointer: the instance."
  A comment and its own code contradicting each other four lines apart.
- **`pasparser_proc.inc`'s interface-parameter by-ref rule** called its
  `UClsIsInterface` clause a "no-op on 64-bit" — true when an interface was 16
  bytes there and `RecSize > 8` already caught it. `RecSize` is 8 on every
  target now, so that clause is the ONLY reason an interface parameter is
  by-ref at all. The code was right and stayed right; the reason it holds had
  changed underneath it, which is the harder kind of stale.
- **`builtinheap.pas`'s PXXIntfAddRef/Release header** named its parameter
  `fatptr` and described word 0 = IMT, word 1 = instance. Both bodies read
  `PMachineWord(p)^` as the instance and have for longer than that.

`RecIsReferenceShaped` is now described by its own question: an interface (one
word) and a method pointer (16 bytes {Code, Data}) differ in WIDTH, and width is
not what that predicate asks. It asks reference-vs-value, which is why both
answer True.

### The node half, and why 59 stays a hole

Both constants were 59, in different namespaces, and both numbers are left
unused. Nothing here is dimensioned by a node-kind count and no table is
positional (checked: the `array[0..63]` hits are scan stacks, and there is no
`AN_LAST`/`IR_MAX`), so a hole costs nothing — while reusing 59 would make every
old IR dump, log line and ticket that names kind 59 silently mean something
else. `tools/iropname_lint.py` recomputes from defs.inc and reports 76 declared
ops, clean.

### The coordination was worth more than the permission

CLAUDE.md says to coordinate node numbering by message, so frank-coordinator got
a "telling, not asking" with a window. What came back was not permission — it
was measurement plus four references **a `compiler/`-scoped census cannot
produce**:

1. `bug-a-pxxcoswitch-and-pxxclone-are-missing-on-riscv32` enumerates the absent
   riscv32 node kinds and IR_IMTADDR was one of them. That ticket reached the
   same conclusion from the OPPOSITE direction — a cross-target arm census, not
   an identifier grep — so the two are genuinely two readings. Updated: six
   becomes five, and riscv32's missing arm is now missing nothing.
2. `devdocs/dev/wasm-target-findings.md`'s code-addresses row: count and list
   both stale. Now 4.
3. **The highest-value one.** `feature-rust-dyn-trait-dispatch` and
   `feature-rust-frontend` both cite `AN_INTF_FROM_CLASS` at "defs.inc ~186-189"
   as the mechanism Rust `dyn Trait` would reuse, and both describe it as a
   fat pointer — *the same stale spec that cost this ticket's sibling two weeks
   at p40, in a second location*. Correcting the wording was not enough: the pxx
   mechanism gets its method table from the RECEIVER'S IDENTITY (an RTTI blob
   reachable from the value), and a `dyn Trait` over a plain struct or a
   primitive has none. So "same shape, generalize the binding" is not the plan
   those tickets thought they had, and both now say so.
4. `tools/iropname_lint.py`'s docstring names it — history, not a break;
   verified clean before and after.

Also cleared by the coordinator, and worth recording because the identifier grep
that answers everything else is structurally blind to it: **a positional table,
whose Nth slot means node kind N and which never names the constant.** There
isn't one. That is the check to run before retiring any node kind, and it is not
a grep for the name.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 787185c01.
