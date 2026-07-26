---
summary: "RTL: ShortMonthNames / LongMonthNames / day-name arrays — lib-test's synapse step is red on them"
type: feature
track: B
prio: 55
---

# RTL: month and day name arrays

- **Type:** feature (library / RTL date formatting) — **Track B**
- **Status:** backlog
- **Opened:** 2026-07-26 — found while wiring [[feature-lib-regex-engine]] into
  `make lib-test`: the target is ALREADY red before that change, and the red was
  not ticketed.

## The red

```
$(PXX_STABLE) --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix \
    test/lib_synapse.pas /tmp/lib_synapse
pascal26:4422: error: undefined variable (ShortMonthNames)
  near: CustomMonthNames n ShortMonthNames >>> n
```

Reproduced on a clean tree (`git stash -u` + `make lib-test`), so it predates the
regex work. `grep -rn ShortMonthNames lib/rtl/*.pas` finds nothing: the RTL simply
has no month-name table.

## Shape

FPC exposes these as writable arrays in `sysutils`, which is what Synapse's date
formatting reaches for:

- `ShortMonthNames: array[1..12] of string` ('Jan'..'Dec')
- `LongMonthNames: array[1..12] of string` ('January'..'December')
- `ShortDayNames: array[1..7] of string`, `LongDayNames: array[1..7] of string`

Writable, because code overrides them for locale-independent output — Synapse
assigns through `CustomMonthNames`. Whether they live in `sysutils` next to the
existing date helpers or in `dateutils` is the implementer's call; `--mimic-fpc`
callers expect the `sysutils` spelling.

## Gate

`make lib-test` reaches and passes the `lib_synapse` step (Track B: build with
`$(PXX_STABLE)`, never rebuild the compiler).
