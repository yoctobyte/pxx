---
track: A
prio: 50
type: bug
blocked-by: []
summary: "The C frontend silently accepts an unknown type name. A struct member of an unknown type vanishes from the struct (the error comes later, as \"no member named 'x'\" at the first access), and a global of an unknown type compiles with no diagnostic. sizeof(p->member) of such a member also compiles. Every missing-typedef problem upstream (a missed include, #include_next, a missing predefine) turns into silently wrong struct layouts, which for a header import means a wrong ABI. Measured 2026-10-05, frank-user master 8be43bcb06, both the Pascal `uses` import path and plain C."
status: done
owner: ""
---

# C frontend accepts unknown type names and drops the declaration

- **Type:** bug (C parser / type resolution) — **Track A**. Silent wrong layout, so prio 50.
- **Filed:** 2026-10-05 from `~/museum_landkaart`, the ESP-IDF header-import census.

## Repro

```sh
printf 'typedef struct { int a; undefined_t x; } s_t;\nstatic inline int g(s_t *p){ return p->x; }\n' > h1.h
printf 'typedef struct { int a; undefined_t x; } s_t;\n' > h2.h
printf 'undefined_t v;\n' > h3.h
for h in h1 h2 h3; do printf 'program p;\nuses %s;\nbegin\nend.\n' $h > p.pas; pascal26 -I. p.pas p; done
# h1: error: C: no member named 'x' in this struct/union   <- wrong diagnostic, wrong place
# h2: compiles   (s_t silently has only `a`)
# h3: compiles
```

## Why it matters

This is what turned the #include_next bug into a puzzle. The member types were
missing, so whole IDF structs silently emptied, and the only symptom was an access
in an inline function 150 lines later. For the header-import feature it's worse
than a crash: a header that "imports fine" can hand Pascal a record with the wrong
size and offsets, and the WiFi driver then reads garbage.

## Expected

`unknown type name 'undefined_t'` at the declaration (as gcc/clang), in both the C
frontend and the `uses` import path.

## Acceptance

h1-h3 fail at the declaration with an unknown-type diagnostic.

## Oracle for header import, once headers parse

~/museum_landkaart/async/src/idfabi.inc holds struct sizes and field offsets that
gcc measured against the same IDF headers (tools/abi_probe.c), e.g.
wifi_init_config_t = 152 bytes with crypto_funcs at 4, wifi_config_t = 184, ap.channel
at 97. An imported record must match them exactly.
