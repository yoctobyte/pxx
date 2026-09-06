---
slug: bug-p-a-class-or-record-body-silently-swallows-any-token-it-does-not-recognise
track: P
prio: 55
type: bug
status: done
owner: ""
created: 2026-09-06
found-by: frankB
blocked-by: [bug-p-a-property-default-value-clause-is-read-as-the-default-indexed-property-marker]
summary: "The class-body member loop (pasparser_decl.inc:7230) and the record-body member loop (:5042) both end in a bare `else Next;` that discards ANY token they do not recognise, with no diagnostic. Measured at 86f935479: a class body containing `42 43 44;`, `+ - * ;` or `'oops';` compiles and runs; so does a record body containing `42 43;`. fpc 3.2.2 refuses all four with a syntax error on the exact line. THIS IS ALSO THE MECHANISM BEHIND THE `default` CLAUSE, and it corrects that ticket: instrumenting the catch-all shows frankB's `... default 16 77 88 99;` firing it FOUR times with kind=tkInteger, so the property value is not consumed by the property parser at all -- all four numbers, the legitimate 16 included, are swallowed here. `default 16` never worked; it was eaten. TWO CENSUSES OVER THE SAME FULLY-PROCESSED 2276-FILE POPULATION LICENSE TWO DIFFERENT ALLOW-LISTS: the class arm fired 6287 times (tkSemicolon 6283, tkVar 4) and the record arm 11 (tkVar 8, tkClass 3, and NO semicolons at all). Every fire in both is legitimate -- stray semicolons, plus section keywords (`var` reopening a field list after a nested `type` section, `class` introducing `class var`) on which pxx matches fpc byte-for-byte -- so each arm must KEEP its own traffic and error only outside it. Class arm allows tkSemicolon and tkVar; record arm allows tkSemicolon, tkVar and tkClass. An earlier partial sweep reporting 323 fires at 100% tkSemicolon is WITHDRAWN: non-recursive glob, never saw the test subdirectories, unreconstructable population -- and its pure-semicolon distribution was an artefact of stopping early, since the tkVar rows appear only late in the full run. LANDING ORDER MATTERS: erroring here before the `default <value>` clause is parsed properly turns legal FPC code into a hard error, so this is blocked-by that ticket, not merely related."
---

# A class or record body accepts arbitrary tokens without a diagnostic

Measured at `86f935479`, binary `760789ae996a`, against fpc 3.2.2:

| probe, inside a body | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `class ... FX: Integer; 42 43 44;` | compiles, runs, prints 7 | `Syntax error, "identifier" expected but "ordinal const" found` |
| `class ... FX: Integer; + - * ;` | compiles, runs, prints 7 | `... but "+" found` |
| `class ... FX: Integer; 'oops';` | compiles, runs, prints 7 | `... but "const string" found` |
| `record ... x: Integer; 42 43;` | compiles, runs, prints 5 | refused |

Two loops, one shape:

```pascal
          else
            Next;        { pasparser_decl.inc:7230 — class body }
```
```pascal
    else
      Next;              { pasparser_decl.inc:5042 — record body }
```

## Why it matters more than a missing diagnostic

**It fails OPEN.** Any construct these loops do not yet support is not reported
as unsupported — it is discarded, and the type is built as if the member were
absent. A feature gap presents as mysterious runtime behaviour instead of a
compile error.

**It decides whether other bugs are visible at all.** A NAME reaching the loop
takes the `tkIdent` branch, is parsed as a field declaration, demands a `:` and
errors loudly. A NUMBER hits the catch-all and vanishes. The same defect is a
hard error or invisible depending on which spelling you probe.

## It is the mechanism under the `default` clause

[[bug-p-a-property-default-value-clause-is-read-as-the-default-indexed-property-marker]]
says the literal *"is consumed somewhere; WHERE is not established and the stray
token does not reach the class-body loop."* Instrumenting both catch-alls and
compiling frankB's own probe:

```
property Depth: Integer read FX write FX default 16 77 88 99;
   -> 4 x CATCHALL cls kind=2 (tkInteger)
```

Four fires, one per number. **The `16` is in there.** The property parser
consumes the `default` keyword, `Eat(tkSemicolon)` finds a number and does
nothing, and the class-body loop then discards every literal in turn. So
`default 16` was never "running correctly with the literal consumed somewhere" —
it compiled because the value was thrown away, which is indistinguishable from
support for a clause that has no effect.

That is the ticket's own warning about probe spelling, one level up: the
observation that made `default 16` look supported was produced by this bug.

## The two censuses, and the two allow-lists they license

Both arms swept over the same 2276-file population (`find test lib/rtl lib/pcl -name '*.pas'`, fully
processed, filenames logged).

| kind | class arm (:7230) | record arm (:5042) |
| --- | --- | --- |
| `tkSemicolon` (78) | **6283** | 0 |
| `tkVar` (7) | **4** | **8** |
| `tkClass` (29) | 0 | **3** |
| anything else | 0 | 0 |
| total fires | 6287 | 11 |
| files firing | 1963 of 2276 | 7 |

**So the fix is two allow-lists:**

| arm | allow | error on |
| --- | --- | --- |
| class body (:7230) | `tkSemicolon`, `tkVar` | everything else |
| record body (:5042) | `tkSemicolon`, `tkVar`, `tkClass` | everything else |

`tkVar` is a `var` section reopening a field list after a nested `type`
section — legitimate in both bodies, witnessed in the class arm by
`test_nested_pointer_alias_is_scoped_to_its_owner` (3 fires) and
`test_generic_nested_type_as_argument`. `tkClass` fires only in RECORD bodies,
because a class body has a real arm for class members and a record body does
not; pxx nonetheless gets `class var` in a record right, matching fpc
byte-for-byte on both sharing and `SizeOf`, so the skip demotes nothing.

**A NUMBER THIS TICKET PREVIOUSLY CARRIED IS WITHDRAWN.** An earlier partial
sweep reported *323 fires, 100% tkSemicolon*, and that figure reached this
ticket's summary and a peer. It used a NON-RECURSIVE `test/*.pas` glob, so it never saw
`test/gui/` — the heaviest firers, at 78-82 fires each — and it was killed at an
unknown point. Its population cannot be reconstructed and I am not reconciling
it against this one: two numbers that cannot be made to agree, where one cannot
be re-run, are not a discrepancy to be settled by argument. **This ticket now
cites one census.** The distribution is the claim; the count is context.

**And the "100% semicolon" reading was itself wrong until the sweep finished.**
At 3802 fires the distribution was still pure `tkSemicolon`; the 4 `tkVar` rows
appear only past that point. The aperture note in the previous version of this
ticket said a non-semicolon kind found later would ADD an arm rather than
invalidate the result. That is exactly what happened, to this ticket's own
author, and it is why the class allow-list has two entries and not one.

**Tree aperture:** the tree moved under the class sweep. I ran `tools/sync.sh`
twice during it to bank commits, and sync pulls; 4 of the 2276 files were
modified by commits that arrived mid-run. The sweep ended at `cf141c5f4`.
Bounded, almost certainly immaterial to the distribution, and recorded because
nothing in the output shows it.

## Landing order — satisfied

`property X: T read F write F default 16;` is legal FPC and common, and while
pxx compiled it by discarding the 16, erroring in this arm would have converted
that into a hard error. So the two changes were only correct as a whole and the
`default` fix had to go first.

It did: `9799ae851` parses a constant expression after `default`, and the
operand no longer reaches this terminus. Confirmed at the instrument rather
than the outcome — with the catch-all logging, `default 16 77 88 99;` fired it
**4** times before that fix and **3** after, the missing one being the
legitimate `16`. This ticket was unblocked by that commit and the narrowing
landed after it.

## The dead-instrument zero, kept because it nearly shipped

My first probe for this bug went on the RECORD loop and fired ZERO on the
known-bad program. That reads as "nothing reaches the catch-all" and would have
been reported as such. The program declared a **class**; the record loop is a
different arm. A census of the wrong arm answers, and answers cleanly.

It was caught only because the positive control ran BEFORE the census rather
than after. Both arms now carry a refusal test for exactly this reason —
`test_a_stray_token_in_a_class_or_record_body_is_refused` and
`test_a_stray_token_in_a_record_body_is_refused`, two files because they are
two arms with different allow-lists, not two spellings of one.


## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 76efae23e.
