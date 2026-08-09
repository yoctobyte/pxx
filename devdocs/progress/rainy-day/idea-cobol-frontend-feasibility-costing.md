---
track: U
prio: 20
type: idea
summary: "COBOL frontend: parser is cheap (grammar is rigid, records map onto Pascal, unstructured flow already proven by BASIC), but it needs a real fixed-point decimal type — Currency is currently a Double — plus PICTURE-edited MOVE and, for full file support, ISAM"
---

# COBOL frontend — what it would actually cost

- **Type:** idea (feasibility costing, not a commitment)
- **Track:** U → re-file into the owning lane if it ever becomes work
- **Status:** rainy-day — costed 2026-08-09 at the user's prompting. Nobody has
  agreed to build this.
- **Owner:** —
- **Related:** [[feature-zig-frontend]], [[idea-ada-frontend-bare-metal-fit]]
- **Lane:** Track **L** (Legacy), shared with Ada — decided 2026-08-09. The
  CLAUDE.md section waits until the lane has code; the reasoning, and why not
  Track H, is in [[idea-ada-frontend-bare-metal-fit]].

## Why it is worth costing at all

The interesting claim is that the IR is now mature enough that a new frontend
is mostly parser work. Zig is the evidence: `zparser.inc` reaches switch,
defer, optionals, error unions, slices and comptime-generics with **zero**
shared-internals changes — no new AST node, no new IR op, no backend edit. If
that holds for a language as unlike Pascal as COBOL, it says something real
about the backend.

## The parser is the cheap half

Measured cost of a frontend in this repo:

| frontend | parser lines |
| --- | --- |
| assembly (`aparser.inc`) | 454 |
| BASIC (`bparser.inc`) | 727 |
| Zig (`zparser.inc`) | 2,054 |
| Rust (`rparser.inc`) | 2,811 |
| C (`clexer` + `cparser`) | 12,227 |
| Nil Python (`pylexer` + `pyparser`) | 26,572 |

COBOL should sit near the low end, for three reasons:

1. **The grammar is rigid.** Verbose, but no indentation sensitivity, no type
   inference, no dynamic typing. It is markedly easier to parse than Python.
2. **The data model maps onto Pascal almost directly.** Level-numbered group
   items are records. `REDEFINES` is a variant record. `OCCURS` is an array.
3. **Unstructured control flow already works.** `bparser.inc` carries 28
   GOTO/GOSUB sites, so `PERFORM THRU` and `GO TO DEPENDING ON` land on proven
   machinery rather than new IR.

Classic COBOL also has **no dynamic allocation at all** — WORKING-STORAGE is
statically laid out. No GC, no ARC, no lifetime analysis, and none of the
variant/container interaction that dominated the Nil Python bug curve. (COBOL
2002 added `ALLOCATE`/`FREE`; refusing them is a legitimate scope line.) This
is the concrete reason COBOL is easier than Ada, whose access types, generics,
exception propagation and above all *tasking* each imply real runtime work.

## The runtime is the expensive half

1. **Fixed-point decimal — the first brick, and currently missing.**
   `lib/rtl/sysutils.pas:278` defines `Currency = Double`, with a comment
   conceding that FPC's is a fixed-point 4-decimal `Int64`. A type whose whole
   job is exact money cannot represent 0.10. This is an FPC-compatibility
   divergence **independent of COBOL** and is arguably worth its own ticket.
   COBOL needs a real one: `COMP-3` packed decimal, zoned `DISPLAY`, and the
   standard's intermediate-precision rules for `COMPUTE`.
   - *Substrate already exists, and more of it than "missing" suggests.*
     `lib/rtl/bignum.pas` (530 lines, signed add/sub/mul/compare, base-10
     string conversion, proven under RSA and P-256). COBOL 2002 permits 31
     digits and a scaled `Int64` runs out at 18, so this is exactly what a
     serious implementation would build on. Nil Python already has **working
     arbitrary-precision integers** on top of this — verified: `2 ** 100` and
     `10 ** 30 // 7` are both exact — via promotable ints whose payload is the
     exact decimal in a managed string. And `compiler/exdec.inc` (520 lines) is
     exact double↔decimal-digit conversion with correct rounding.
   - *So what is actually missing is narrower than "a decimal type":* the
     scaled fixed-point **arithmetic** — a bigint mantissa plus a scale, with
     decimal-aware add/sub/mul/div, rounding modes and the standard's
     intermediate-precision rules. The big-integer half and the digit-string
     half are both already built and in production use. Note the codebase says
     "decimal" for the *conversion* core, not for an arithmetic type; there is
     no type named `Decimal` in the tree.
   - *Rounding:* `Round` is already half-to-even (verified: 0.5→0, 1.5→2,
     2.5→2, -2.5→-2). Note this is the mode COBOL uses **least** — plain
     arithmetic truncates, bare `ROUNDED` is half-away-from-zero, and
     half-to-even is the optional `ROUNDED MODE IS NEAREST-EVEN`. So the work
     is a mode selector, not a rounding algorithm.
2. **PICTURE-edited MOVE.** `PIC ZZZ,ZZ9.99-` with zero suppression, insertion
   characters and floating signs is a small language, and `MOVE` between
   mismatched pictures has its own truncation and alignment rules. Pure library
   work, no IR involvement, and where real implementations spend their time.
3. **Indexed/relative files.** Sequential I/O is free; `ORGANIZATION INDEXED`
   with record keys is ISAM. Note the project already compiles SQLite from
   source through the C frontend, so that is a back end we own rather than one
   we would write.

## The thing to not underestimate

COBOL is **wide, not deep**. The expression language and type system are thin —
none of the machinery that made Nil Python expensive. But the statement set is
large and several verbs are subsystems: `EVALUATE` (decision tables), `INSPECT
... TALLYING/REPLACING` (text processing), `STRING`/`UNSTRING`, `SEARCH ALL`
(binary search as a verb), `SORT`/`MERGE` (external sort with user input/output
procedures), `COPY ... REPLACING` (a macro layer), and the Report Writer (a
declarative reporting sublanguage). COBOL 2002 even has OO — classes,
interfaces, inheritance — which a subset may simply refuse.

Cheap parser, long tail of library verbs. A useful subset is a bounded project;
"COBOL, complete" is not.

## If it is ever picked up

Scope it as a subset with an explicit refusal list (Report Writer, OO COBOL,
`ALLOCATE`) rather than an open-ended conformance goal, and build the decimal
type **first** — it is the part every COBOL program is made of, and the part
where "mostly right" is worth nothing.

## Log
- 2026-08-09 — costed against the current tree. Not scheduled.
