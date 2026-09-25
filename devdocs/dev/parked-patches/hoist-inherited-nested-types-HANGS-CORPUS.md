# hoist-inherited-nested-types-HANGS-CORPUS.patch

> **WARNING: THIS PATCH HANGS THE FPC CORPUS PROBE.** The stash message says
> so outright: "partial: fixes E/r10, HANGS the corpus". Do not apply it to a
> tree that a corpus run, a pin or a gate will build from. Find and fix the
> hang first; the likely suspect is the ancestor walk in
> CollectHoistCandidates (a `guard < MAX_HOISTED_NESTED` bound is the only
> thing that ends that loop).

Parked 2026-09-25 at the wrap-up, from frankS's stash dated 2026-09-09
(base 9fd2efce69). It does NOT apply cleanly to the current tree; expect to
redo it by hand in compiler/pasparser_generic.inc. It is the only file the
patch touches (+69/-5).

WHAT IT DOES: a generic's nested type is hoisted to a per-specialization name
(`TWithPointers$LongInt$PT`), but only the template's OWN nested types were
candidates. An INHERITED one (`PT = ^T` declared in an ancestor template,
named as a generic argument in a descendant) kept the bare spelling, so every
specialization minted the same `TEnum$PT`. The result was "duplicate class
name" on the second one and `unknown type: PT` on the first.
CollectHoistCandidates now walks the ancestor chain as well.

HOW FAR IT GOT: it fixed the E/r10 reproduction and hung the corpus. The
cause of the hang was not found. The patch's own comment records a known
limit: a descendant that renames the parameter it passes up leaves `T`
unsubstituted and fails loudly. Tickets in the same family: `ls
devdocs/progress/*/ | grep nested-type`.
