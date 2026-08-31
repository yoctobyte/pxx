---
track: P
prio: 40
type: feature
status: backlog
found: 2026-08-31
found-by: frank-user-a2, shape confirmed by frankC
owner: ""
blocked-by: []
summary: "`library foo;` does not parse -- `expected 'begin' before 'library'`. It is a FRONTEND gap (Track P), not an output gap: the x86-64 object writer landed at 41045d7b4 and already exports a link surface, so `library` + `exports` would be a second, DECLARATIVE spelling of what `cdecl` on a definition says today. That makes it a compat/ergonomics feature rather than a capability one, which is why it is p40 and not p80. The real question it forces is whether `exports` may export a routine that is NOT cdecl -- FPC allows it, and the object writer deliberately refuses to, because an internal-convention routine exported under its Pascal name is callable and wrong. Answer that before implementing."
---

# A Pascal `library` unit does not parse

```
$ pascal26 --shared foo.pas foo.so
foo.pas:1: error: expected 'begin' before 'library'
```

Deferred by [[meta-a-pxx-produces-linkable-code]] until the object writer's
shape was known.

## What it is worth, now that the writer exists

**Less than it looked.** The reason to want `library` was that nothing could
express an export surface. Something can:
[[feature-a-a-general-x86-64-relocatable-object-writer]] exports the
C-convention routines (`ProcCdecl`) under their own names, so a `cdecl` on the
definition is already the working spelling.

`library` + `exports` would be a second, *declarative* spelling of the same
thing — worth having for source compatibility with real FPC/Delphi code, which
is the compat axis, not the capability one. Hence p40.

## The design question to settle first, because it is not cosmetic

**May `exports` export a routine that is not `cdecl`?** FPC lets you, and the
object writer deliberately does not: an internal-convention routine exported
under its Pascal name is *callable and wrong* from anything outside pxx — the
foreign caller marshals SysV, the callee reads pxx's internal convention, and
nothing diagnoses it.

Three answers are available and they are genuinely different features: reject
it; accept it and make `exports` imply `cdecl`; or accept it and export it under
the pxx convention for pxx-to-pxx linking. Pick one **before** writing the
parser — this is a Track U-shaped fork sitting inside a Track P ticket, and
the compat ceiling applies (we do not chase FPC parity; we care that correct
Pascal compiles correctly).

Note also that `--shared` for compiled sources is a separate blocker with its
own backend dependency — [[feature-a-shared-library-output-for-compiled-sources]] —
so `library` landing does not by itself produce a `.so`.

## Umbrella

[[meta-a-pxx-produces-linkable-code]]
