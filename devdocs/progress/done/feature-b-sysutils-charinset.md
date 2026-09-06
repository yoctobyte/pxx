---
track: B
prio: 40
type: feature
blocked-by: []
status: done
owner: "frankD"
created: 2026-09-06
summary: "FIXED 2026-09-06, together with AnsiDequotedStr. `lib/rtl/sysutils.pas` declared TSysCharSet — and its own comment named that type as 'the parameter type of the CharInSet / character classification family' — while never declaring CharInSet itself. The type was present and named after the function; the function was absent. FPC's is `function CharInSet(Ch: AnsiChar; const CSet: TSysCharSet): Boolean; inline;`, a one-line `Ch in CSet`, and it exists because Delphi-compatible code cannot write `Ch in Set` when Ch is a WideChar. Added with AnsiDequotedStr in one commit because fcl-passrc needs both and neither was visible until the parse wall in front of it fell: pscanner.pp:559 for this one, pparser.pp:4467 for the other. THE CAUTION IN THIS TICKET WAS RIGHT AND WAS FOLLOWED — it said a one-line body is exactly what gets closed on a build rather than a run, so both functions are DRIVEN, twelve rows against fpc 3.2.2 -Mobjfpc, asserting both answers of the predicate plus the empty set. Test `test_sysutils_charinset_and_ansidequotedstr`."
---

# sysutils.CharInSet

- **Type:** feature (compat — FPC/Delphi RTL function absent) — **Track B**
  (`lib/rtl/sysutils.pas`).

```pascal
function CharInSet(Ch: AnsiChar; const CSet: TSysCharSet): Boolean;
begin
  Result := Ch in CSet;
end;
```

The one-line body is the whole function in FPC too; it exists for the Delphi
`WideChar` overload's sake, not for the AnsiChar one.

## Why it is filed rather than fixed on the spot

Found by Track P while cutting `pparser.pp` down to localise a parse error — it
is behind two parse walls and cannot be reached by compiling the unit today, so
**nothing here has been measured end-to-end**. The declaration is trivial; what
is not established is whether pxx's `TSysCharSet` and its `in` operator accept
this exact shape, and a one-line addition that compiles is not evidence the call
site works. Whoever takes it should drive it from a program, not build it.

## Gate

Assert a value on BOTH answers — `CharInSet('A', ['A'..'Z'])` true and
`CharInSet('a', ['A'..'Z'])` false. A predicate that returns a constant passes a
one-row test, and the failure mode here (an empty or mis-built set) is exactly
the one that returns the same answer for every character.


## Resolution — 2026-09-06

Both landed together. `CharInSet` is the one-liner the ticket predicted;
`AnsiDequotedStr` is not, and its three non-obvious cases are FPC's behaviour
rather than choices, so each has its own row:

- a string that does **not start** with the quote is returned WHOLE and
  unexamined — `ab'cd` keeps its inner quote. An implementation that "strips
  quotes wherever it finds them" passes every other row and fails this one.
- a **doubled** quote is an escape: `'ab''c'` is `ab'c`.
- an **unterminated** quote consumes to the end rather than raising.

I would have got at least the first of those wrong from reading FPC's source —
it falls out of `AnsiExtractQuotedStr`'s `exit(strpas(P))` rather than being
stated anywhere — which is the reason every row is compared against the running
fpc binary and not against my reading of it.

Written over the string rather than over a PChar cursor: FPC's `var Src: PChar`
exists so `AnsiExtractQuotedStr` can report where it stopped, and nothing here
has that caller. If one appears, add `AnsiExtractQuotedStr` beside it rather
than reshaping this.

The gate this ticket asked for — assert BOTH answers of the predicate — is met,
plus the empty set, because the failure mode named here (an empty or mis-built
set) returns the same answer for every character.

## Log

- 2026-09-06 — fixed, commit ffefbeeb3.
