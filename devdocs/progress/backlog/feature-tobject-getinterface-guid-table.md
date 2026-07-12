---
prio: 50
---

# TObject.GetInterface(IID, out obj) — needs an interface GUID table

- **Type:** feature (Track A — RTTI / interfaces)
- **Track:** A — core (rtti_emit.inc, interface tables)
- **Status:** backlog — opened 2026-07-13.
- **Blocks:** [[feature-pascal-corpus-fpcunit]] (testutils.pp:43 —
  `TNoRefCountObject.QueryInterface` calls `GetInterface(IID, Obj)`).

## Why it is not a five-minute stub
FPC's `TObject.GetInterface(const IID: TGUID; out Obj): Boolean` looks an implemented
interface up **by GUID** at runtime and hands back the interface pointer.

**pxx interfaces default to CORBA and carry no GUIDs at all.** There is no table to
search, so nothing can be looked up.

The tempting shortcut — make GetInterface always return False — would let testutils
COMPILE and move the fpcunit chain to its next wall. **Do not.** A class that really
does implement the interface would then be told it does not, silently, with no
diagnostic. That is exactly the "compat finding that means silent wrong behavior"
the track rules say to promote to a real bug rather than paper over. If a stub is
ever wanted as a deliberate stepping stone it must be behind a flag and must say so.

## What it actually needs
1. **Record the GUID** an interface declares (`['{...}']`) — the parser currently
   accepts the literal and discards it.
2. **Emit an interface table per class**: for each implemented interface, {GUID, IMT
   pointer}. The IMT itself already exists (built per implemented interface at class
   parse time) — only the GUID key and a table to search are missing.
3. `GetInterface` walks that table (own + inherited), compares the 16-byte GUID, and
   on a hit stores the fat pointer {IMT, instance} into the out param.
4. It should reach the table the same way published-method reflection does — via the
   instance->RTTI backlink at VMT-8 that [[feature-rtti-method-reflection]] added.

Consider whether this should also imply `{$interfaces com}` semantics; it need not —
a GUID table is orthogonal to refcounting, and CORBA interfaces may carry GUIDs.

## Gate
`make test` + self-host byte-identical + cross. Interface layout changes, so
byte-identical self-host is the check that matters.

## Log
- 2026-07-13 — opened. Split out of [[feature-pascal-corpus-fpcunit]] once
  MethodAddress/MethodName landed and GetInterface became the only remaining
  compile blocker in testutils.
