---
prio: 55
---

# Nested variant parts with a tagged discriminant (`case f: T of` inside a variant arm)

- **Type:** bug / feature gap (Pascal frontend — record parser) — **Track P**
  (shared parser, A's gate)
- **Status:** done
- **Opened:** 2026-07-12, the synsock wall of [[feature-synapse-compile-check]]
  ("expected field name in variant part").

## Symptom

Synapse's `ssfpc.inc:357` `TVarSin` — the sockaddr union every synsock
function passes around:

```pascal
TVarSin = packed record
  case integer of
    0: (AddressFamily: sa_family_t);
    1: (
      case sin_family: sa_family_t of      { <- tagged discriminant, NESTED }
        AF_INET:  (sin_port: word;
                   sin_addr: TInAddr;
                   sin_zero: array[0..7] of byte);
        AF_INET6: (sin6_port: word;
                   sin6_flowinfo: longword;
                   sin6_addr: TInAddr6;
                   sin6_scope_id: longword);
        );
end;
```

Three combined shapes PXX's variant parser rejects here:
1. a variant ARM whose body is itself a `case ... of` (nested variant part);
2. a TAGGED discriminant (`case sin_family: sa_family_t of` — the tag is a
   real field, not just a selector type);
3. non-integer-literal case labels (`AF_INET`/`AF_INET6` — declared consts).

`devdocs/progress/done/` has the flat variant-overlap work
(project_variant_record_overlap_done) — this is the recursive/tagged
extension of that.

## Why it matters

`TVarSin` is THE parameter type of the whole synsock surface (`SizeOfVarSin`,
bind/connect/accept wrappers) — blcksock/httpsend/smtpsend/pop3send/ftpsend
all stop here. With [[bug-cast-deref-as-varparam-arg]] this is one of the two
remaining walls in front of the entire Synapse stack.

## Acceptance

- Nested variant parts parse recursively; a tagged discriminant declares its
  tag as an ordinary field at the variant offset; const case labels resolve.
- Layout matches FPC (all arms overlay at the variant start; record size =
  max arm end; packed respected) — verify with SizeOf(TVarSin) against FPC.
- synsock.pas compiles past line 435; self-host byte-identical.

## Log
- 2026-07-12 — resolved, commit 541f8fda.
