---
summary: "class CONSTS are unscoped globals, so visibility (tclass12b: strict private const reached from a descendant) cannot be enforced on them; needs a class-const registry + name-resolution gate"
type: bug
track: P
tags: compat
prio: 20
---

# class-const visibility unenforced (tclass12b residual)

- **Split from:** [[bug-pascal-member-visibility-unenforced]] (its last open
  item). Fields (23fd7574) and methods (df41ab5e) are enforced under
  --strict-visibility (now also on under --mimic-fpc); class CONSTS are not.
- **Why:** a class-body `const` section parses as ordinary GLOBAL constants —
  pxx does not scope class-local declarations, so at an access site there is no
  (class, visibility) to check and a bare reference resolves via FindSym from
  anywhere.
- **Direction:** registry ClassConstCi/Name/Vis stamped in the class-body const
  parse; enforce at the qualified `TClass.ConstName` resolution AND gate bare
  FindSym hits that shadow-resolve to another class's const. tclass12b
  (`strict private const` from a descendant) is the conformance reminder; it
  stays skip-listed pointing here.
- **Value:** conformance-only (FPC-valid code cannot trip it — it only REJECTS
  more); low prio.
