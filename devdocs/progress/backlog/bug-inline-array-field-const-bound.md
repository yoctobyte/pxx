---
prio: 48  # auto — narrow parser gap; named-alias sidesteps it, but it's a real dialect hole
---

# Inline record-field `array[0..CONST - 1]` fails to parse (const-EXPRESSION bound)

- **Type:** bug (frontend — parser, inline array-type in a record field)
- **Track:** A (`parser.inc` array-type / record-field parsing). Filed from
  Track B (dns_cache) — hand off, do not fix under B/E.
- **Status:** backlog — filed 2026-07-11.
- **Owner:** —

## Symptom
An **inline anonymous array field** whose subrange high bound is a **constant
expression** (`CONST - 1`) fails: `Expected: ], but got: <ident> (Kind: 1)`.
The same array as a **named type alias** compiles, and an inline field with a
**literal** bound compiles — so it is specifically the inline-field + const-expr
combination. Live at pinned v197 (and by construction at HEAD — parser path).

## Repro
```pascal
program rc;
const N = 8;
type
  TE = record v: Integer; end;
  TC = record slots: array[0..N - 1] of TE; end;   { <-- Expected: ], but got: N }
var c: TC;
begin c.slots[0].v := 5; writeln(c.slots[0].v); end.
```

Green variants (all verified):
- **Named alias:** `TEArr = array[0..N - 1] of TE; TC = record slots: TEArr; end;`
- **Literal inline bound:** `slots: array[0..7] of TE;`
- Const-expr in a top-level array-type alias (e.g. `TDnsIpv4Array =
  array[0..DNS_MAX_IPS - 1] of LongWord` in dns_wire_core) already works.

So the range parser handles `0..CONST-1` everywhere EXCEPT an inline array type
in a record-field position — likely a field-declaration path that parses the
low bound + `..` then calls a stricter "expect `]` or a simple bound" branch
instead of the full const-expression parser used by named type decls.

## Impact
Low-severity but a real dialect hole (FPC accepts the inline form). Worked
around in `lib/rtl/dns_cache.pas` by naming the slot array
(`TDnsCacheSlots = array[0..DNS_CACHE_SLOTS - 1] of TDnsCacheEntry`) — which is
arguably cleaner, so no ugly code was left behind, but the parser should accept
the inline form.

## Gate
`make test` + self-host byte-identical; add a `.pas` regression mirroring the
repro (inline const-expr-bound array field reads/writes correctly).
