---
slug: bug-p-a-class-or-record-body-silently-swallows-any-token-it-does-not-recognise
track: P
prio: 55
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankB
blocked-by: [bug-p-a-property-default-value-clause-is-read-as-the-default-indexed-property-marker]
summary: "The class-body member loop (pasparser_decl.inc:7230) and the record-body member loop (:5042) both end in a bare `else Next;` that discards ANY token they do not recognise, with no diagnostic. Measured at 86f935479: a class body containing `42 43 44;`, `+ - * ;` or `'oops';` compiles and runs; so does a record body containing `42 43;`. fpc 3.2.2 refuses all four with a syntax error on the exact line. THIS IS ALSO THE MECHANISM BEHIND THE `default` CLAUSE, and it corrects that ticket: instrumenting the catch-all shows frankB's `... default 16 77 88 99;` firing it FOUR times with kind=tkInteger, so the property value is not consumed by the property parser at all -- all four numbers, the legitimate 16 included, are swallowed here. `default 16` never worked; it was eaten. TWO CENSUSES MAKE THE FIX NARROW AND THEY DISAGREE WITH EACH OTHER, so the two arms need DIFFERENT allow-lists: the class loop fired 323 times, 100% tkSemicolon and zero of anything else, while the record loop fired 11 times over a fully-processed 2273-file population -- tkVar x8 and tkClass x3, and zero semicolons. The record traffic is legitimate (advanced-record section keywords: `var` reopening a field section, `class` introducing `class var`; pxx matches fpc byte-for-byte on both, so nothing is being demoted), so erroring on it would break seven passing tests. Class arm allows tkSemicolon; record arm allows tkVar, tkClass, tkSemicolon; both error on everything else. LANDING ORDER MATTERS: erroring here before the `default <value>` clause is parsed properly turns legal FPC code into a hard error, so this is blocked-by that ticket, not merely related."
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

## The census, and the fix it licenses

Probe on the class-body catch-all logging kind and spelling, swept over the test
tree plus `lib/rtl` and `lib/pcl`:

| | |
| --- | --- |
| fires observed | **323** |
| distinct token kinds | **1** |
| that kind | **tkSemicolon** (Ord 78) |
| non-semicolon fires | **0** |

So the entire legitimate traffic through this arm is skipping stray semicolons,
and **the fix is a narrowing, not a removal**: an explicit `tkSemicolon -> Next`
arm, `Error` on everything else.

**Ordinals confirmed three ways, not one.** A 1-based `grep -n` over the
`TTokenKind` list in `defs.inc:1902` names `tkRBrack` for 78 and sends the reader
after brackets. The 0-based count gives `tkSemicolon`, and the probes above agree
independently: integers reported 2 = `tkInteger`, `'oops'` reported 3 =
`tkString`, and `+ - *` reported 70/71/72 = `tkPlus`/`tkMinus`/`tkStar`.

**Aperture:** the sweep was killed for memory partway through a 2048-file set and
printed its file count only at the end, so the denominator is unknown. 323/323
with zero exceptions is strong, not complete. A non-semicolon kind found later
ADDS an arm; it does not invalidate this one.

**The record loop is a separate population and it is gated the same way.** pxx
accepts a `property` inside a plain record (fpc 3.2.2 refuses it outright:
`"END" expected but "PROPERTY" found`), and the record loop has its own
`tkProperty` arm at :4985 — so `record FX: Integer; property Depth: Integer read
FX write FX default 16; end` reaches the record catch-all by exactly the route
the class one does. Narrowing either arm before the `default <value>` clause is
parsed breaks the same legal code, so both wait on the same ticket.

## Landing order — this is why `blocked-by` and not `related`

`property X: T read F write F default 16;` is legal FPC and common. Today pxx
compiles it by discarding the 16. **Erroring in this arm before the `default
<value>` clause is parsed properly converts that into a hard error**, so the two
changes are only correct as a whole and the `default` fix goes first.

## A note for whoever censuses the record loop

My first probe went on the record loop and fired ZERO on frankB's known-bad
program — a dead-instrument zero, and it would have been reported as "nothing
reaches the catch-all" had the positive control not run first. The reason is
plain in hindsight: frankB's program declares a **class**, and the record loop
is a different arm. Assert your probe fires on a case you know reaches it,
in the population you are actually asking about.

## 2026-09-06 (frankD) — the record census, complete, and it inverts the class one

**2273/2273 files processed** (test tree plus `lib/rtl` and `lib/pcl`; the
population size is printed first this time, and the progress line goes to a
file so a pipe cannot buffer it away). 11 fires, all attributed:

| kind | count | witnesses |
| --- | --- | --- |
| `tkVar` (7) | 8 | `test_record_nested_type_section` (3), `test_nested_pointer_alias_is_scoped_to_its_owner` (2), `test_class_const_b263`, `test_record_local_advanced_fail`, `test_record_rules_ok` |
| `tkClass` (29) | 3 | `test_class_property_through_an_instance` (2), `test_class_property_backed_by_a_class_var` |
| `tkSemicolon` (78) | **0** | — |

**Exactly inverted from the class arm** (323 fires, 100% semicolon, zero of
anything else). The two arms have disjoint live traffic, so ONE allow-list is
wrong for both.

**And the record arm's traffic is legitimate.** These are advanced-record
SECTION KEYWORDS — `var` reopening a field section after a nested `type`
section, and `class` introducing `class var`. Something else consumes the
members by lookahead; the catch-all is where the section keyword itself gets
eaten. Probed against fpc 3.2.2:

```pascal
type TR = record
  class var Shared: Integer;
  var Own: Integer;
end;
```

pxx and fpc agree byte-for-byte — `Shared` stays shared across instances, `Own`
does not, `SizeOf(TR)` is 4 in both. So skipping the keyword is not silently
demoting a class var to an instance field, and erroring on `tkVar`/`tkClass`
would break seven passing tests on day one.

**So the fix is two different allow-lists, not one:**

| arm | allow | error on |
| --- | --- | --- |
| class body (:7230) | `tkSemicolon` | everything else |
| record body (:5042) | `tkVar`, `tkClass`, `tkSemicolon` | everything else |

`tkSemicolon` is in the record list on symmetry, not on evidence — the corpus
produced none there. It costs nothing and a stray `;` is legal in both bodies.

Instrument aperture, stated because it cost a second pass: **the census script
logged the token KIND and not the FILE.** Attribution needed a re-run over the
three bands where the running count moved. A census that cannot name its own
witnesses gets run twice; log the filename from the first line.

