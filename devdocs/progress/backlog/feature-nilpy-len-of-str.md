---
track: N
prio: 50
type: feature
---

# NilPy: len() on a str (only TPyList is accepted today)

Found 2026-07-19 while landing [[feature-nilpy-str-methods]]; pre-existing,
NOT caused by that change.

```python
s = "abc"
print(len(s))
```
```
pascal26:2: error: no overload of len matches these arguments ()
```

pylib declares only `len(l: TPyList): Integer`, so a string argument finds no
overload. `len()` on strings is everywhere in Python generally and in uforth
specifically, so milestone 1 needs it.

Fix shape: add `len(const s: AnsiString): Integer` to pylib next to the list
one and let the existing overload machinery pick. Watch the landmine recorded
in `project_builtin_overload_shadows_used_unit` — a builtin overload COMPETES
with a used-unit routine and argument width steers the pick, so verify both
`len(list)` and `len(str)` still resolve after adding it.

Note the error also dumps the compiler's raw MatchProcCall candidate table
(`arg[0] = ...` / `param[0] = ...`) to stdout, which reads like stray debug
output in a user-facing diagnostic. Possibly worth its own cleanup ticket.
