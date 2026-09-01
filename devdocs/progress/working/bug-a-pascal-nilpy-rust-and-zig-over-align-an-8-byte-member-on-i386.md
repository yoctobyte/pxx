---
track: A
prio: 45
type: bug
found: 2026-09-01
found-by: frankC
summary: "PASCAL DONE AND PROVEN; NilPy, Rust and Zig still open. The four `fAlign := TypeAlign(fTk)` record-field sites in pasparser_decl.inc now call TypeFieldAlign, and a new mixed-link oracle (test-record-abi-mixed-link) judges the layout against gcc across a real link on x86_64 and i386, four shapes plus a value round trip through a `cvar` record global. The Track U fork this ticket flagged -- whether a Pascal record must match the C ABI -- dissolved on the first measurement: pxx's C frontend answered 12/4 and pxx's PASCAL frontend 16/8 for the same fields, same target, same compiler. It was not an FPC question, it was one compiler disagreeing with itself. N/R/Z have no export spelling and so no mixed link, and rustc/zig i686 are not on this box."
status: working
owner: frankA
tags: [abi, i386, layout, record, mixed-link]
---

# Pascal, NilPy, Rust and Zig over-align an 8-byte member on i386

`TypeFieldAlign` (`compiler/symtab.inc`) is the ABI-correct member alignment:
natural everywhere, capped at 4 on i386. It exists because a `double` inside a
struct aligns to 4 there — measured, `gcc -m32`, `struct MIX {int a; double y;}`
is sizeof 12 with `y` at 4.

Only `cparser.inc:13116` reads it. The other four frontends compute member
offsets from `TypeAlign`, which is now documented as the *storage* answer:

| frontend | lines | construct |
| --- | --- | --- |
| Pascal (P) | `pasparser_decl.inc` 3068, 3165, 3973, 5788 | `record` fields |
| NilPy (N) | `pyparser.inc` 33588, 33667, 33865, 34406, 34563 | struct/union fields |
| Rust (R) | `rparser.inc` 4537–4538, 4589–4590, 4651–4652, 4676–4677 | struct fields |
| Zig (Z) | `zparser.inc` 1622–1623 | struct fields |

`rparser.inc:447` (`RPayloadAlign`) is an enum PAYLOAD slot — storage, not a
member — and should keep calling `TypeAlign`. Check each site for which of the
two questions it is asking before substituting; that distinction is the whole
bug and one caller already looked like the other.

## Why this is not four one-line commits

**Each frontend's i386 layout is currently self-consistent, so no pxx-only test
can go either red or green on the change.** The C fix was provable only because
`test-c-abi-mixed-link` links a gcc translation unit against a pxx one and reads
the fields across the boundary. Nothing equivalent exists for the other four,
and `gcc -m32` is not an oracle for a Rust or Zig layout anyway — the oracle for
R is `rustc --target i686-unknown-linux-gnu` on a `#[repr(C)]` struct, for Z it
is `zig build-obj -target x86-i686-linux` on an `extern struct`, and neither
toolchain is on this box.

For **P and N** the question is not even settled: Pascal's `record` is not
required to match the C ABI unless it is `packed` or reached through a `cdecl`
boundary, so the change may be right only for the interop path. That is a Track
U question if it does not fall out of the first measurement.

**Do not do these as a batch.** The layout of a record is reachable by every
program in that language; the C change was worth its risk because a gate proved
it and because the C frontend's entire purpose is agreeing with C.

## What would make it cheap

An i386 mixed-link oracle per frontend, built the way the C one was: a pxx
object exporting a struct-valued function, a gcc `-m32` object reading the
fields, one link. For P that is achievable today — Pascal `cdecl` + gcc is
exactly the C gate's shape with the subject swapped.

Split off from [[bug-a-an-8-byte-scalar-is-over-aligned-inside-a-struct-on-i386]].


## PASCAL: DONE AND PROVEN

### The fork dissolved on the first measurement

This ticket flagged a Track U question: a Pascal `record` is not required to
match the C ABI unless it is `packed` or crosses a `cdecl` boundary, so the
change might be right only for the interop path. One measurement retired it,
and it is not the measurement the ticket expected.

Same four fields, same target, same compiler, one `gcc -m32` link:

    pxx-C: sizeof=12 offy=4   pxx-Pascal: sizeof=16 offy=8

**pxx disagreed with itself.** Not with FPC, not with gcc alone — its own C
frontend and its own Pascal frontend gave different offsets for
`{int a; double y;}` in one invocation family. Whatever the right i386 record
layout is, it cannot be two answers inside one compiler for the same shape, and
a `record` reaches C through `cdecl` and now through a `cvar` global. There was
nothing left for Track U to rule on.

(No FPC oracle was available and none was needed: only `ppcx64` is installed,
`ppc386` is absent. The relevant authority is the platform ABI, which `gcc -m32`
states directly.)

### The change

All four `fAlign := TypeAlign(fTk)` sites in `pasparser_decl.inc` — the line
numbers in the table above had gone stale, they are 3139, 3236, 4044 and 5875 —
now call `TypeFieldAlign`. Each was already a member-alignment question; the
`{$PACKRECORDS}` cap at 4044 still applies afterwards, cap over cap.

### The oracle, which is the durable half

`test-record-abi-mixed-link`, wired into testmgr's `limited` and `full` tiers
beside `test-c-abi-mixed-link`. It is the C gate's shape with the subject
swapped, as the "what would make it cheap" section asked for, and it compares
**three** answers rather than two: gcc's own copy of every struct, pxx's C
frontend, pxx's Pascal frontend. Two of the three come from one compiler and
would agree by construction — which is precisely the state that let this
survive.

Four shapes (`{int,double}`, `{char,long long}`, `{double,char}`, a nested
record) plus a value round trip: the gcc main writes both fields of a Pascal
`cvar` record global through its own definition, and Pascal reads them back.

| | before `b8e0b2d5a13e` | after `0e26cecc0d0d` |
| --- | --- | --- |
| i386, all four shapes | **MISMATCH** on every one (16/8, 16/8, 16/8, 24/8 against gcc's 12/4, 12/4, 12/8, 16/4) | agree |
| i386 round trip: C writes `y=2.5`, Pascal reads | **wrong value, no diagnostic** | correct |
| x86_64, all four shapes + round trip | agree | agree |

The x86_64 arm is not decoration. Nothing in the fix touches it, so it is what
says the fixture measures LAYOUT rather than something i386-shaped: green in
both arms, on the same fixture whose i386 arm mismatched four ways.

The round-trip row is the one worth keeping in mind. The offset rows say the
layouts differ; that row says what it costs — C wrote at offset 4, Pascal read
from offset 8, and the program got a wrong `double` with nothing printed
anywhere.

`make test-i386`, `test-c-abi-cross`, `test-emit-obj` and `gate.sh quick` all
green after. (`test-c-conformance-i386` SKIPs — the c-testsuite corpus is not
installed on this box, so that row saw nothing either way.)

## STILL OPEN: NilPy, Rust and Zig — and the blocker is sharper than "no oracle"

Unchanged, deliberately. The ticket said not to do these as a batch and that
each is self-consistently verified only; the Pascal fix does not make the other
three provable, and here is the specific reason for each:

- **NilPy, Rust, Zig cannot produce a mixed link at all.** `ProcCdecl` is set
  from `pasparser_*` and `cparser.inc` and nowhere else, so none of the three
  has an export spelling — there is no `.o` with a callable symbol to link a
  gcc `main` against. That is a prerequisite, not a testing detail, and it is
  the same fact that stops them producing a `.so`
  ([[meta-a-pxx-produces-linkable-code]]).
- **`gcc -m32` is not the oracle for R or Z anyway.** Rust's is `rustc --target
  i686-unknown-linux-gnu` on a `#[repr(C)]` struct and Zig's is `zig build-obj
  -target x86-i686-linux`; neither toolchain is on this box.
- For **N**, CPython is the oracle for semantics and says nothing about struct
  layout, so even with an export spelling the reference would have to be gcc,
  via NilPy's own C-interop claim.

So the honest next step for those three is an export spelling, not a layout
edit. Landing the substitution unproven in three frontends is exactly what this
ticket was filed to prevent.
