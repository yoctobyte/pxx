---
track: A
prio: 45
type: bug
blocked-by: []
summary: "A `uses`-imported C header exports object-like #defines to Pascal only when the body is a literal or an expression: `#define LIT 7` and `#define E (LIT + 1)` work, but `#define A LIT` (alias of a macro), `#define T my_true` (alias of true/false) and `#define A E_TWO` (alias of an enum constant) are 'undefined variable' in Pascal. In ESP-IDF that loses 8 of the 70 ABI values the app needs, e.g. WIFI_DYNAMIC_TX_BUFFER_NUM (= CONFIG_ESP_WIFI_DYNAMIC_TX_BUFFER_NUM), WIFI_STA_DISCONNECTED_PM_ENABLED (= true), SNTP_OPMODE_POLL (= ESP_SNTP_OPMODE_POLL). Measured 2026-10-05, frank-user master 722eff275f."
status: done
owner: ""
---

# C import drops object macros whose body is a bare identifier

- **Type:** bug (C header import, macro export) — **Track A**.
- **Filed:** 2026-10-05 from `~/museum_landkaart`, the ESP-IDF ABI check.

## Repro

```sh
cat > mh.h <<'H'
#define LIT 7
#define ALIAS_MACRO LIT
#define EXPR_MACRO (LIT + 1)
#define my_true 1
#define ALIAS_TRUE my_true
enum e { E_ONE = 1, E_TWO };
#define ALIAS_ENUM E_TWO
H
for n in LIT ALIAS_MACRO EXPR_MACRO ALIAS_TRUE ALIAS_ENUM; do
  printf 'program p;\nuses mh;\nvar v: Int64;\nbegin\n  v := %s;\n  writeln(v);\nend.\n' $n > p.pas
  pascal26 -I. p.pas p && ./p
done
# LIT: 7   EXPR_MACRO: 8
# ALIAS_MACRO / ALIAS_TRUE / ALIAS_ENUM: error: undefined variable
```

## Real-world

ESP-IDF esp_wifi.h's WIFI_INIT_CONFIG_DEFAULT() ingredients follow the pattern
`#if CONFIG_X  #define WIFI_X CONFIG_X_NUM  #else  #define WIFI_X 0  #endif`. On the
taken branch they're aliases, so these are missing: WIFI_DYNAMIC_TX_BUFFER_NUM,
WIFI_RX_MGMT_BUF_NUM_DEF, WIFI_DEFAULT_RX_BA_WIN, WIFI_SOFTAP_BEACON_MAX_LEN,
WIFI_MGMT_SBUF_NUM, WIFI_STA_DISCONNECTED_PM_ENABLED (true), WIFI_DUMP_HESIGB_ENABLED
(false), SNTP_OPMODE_POLL (enum). The same names on the `0` branch import fine
(WIFI_STATIC_TX_BUFFER_NUM). Item D (WIFI_INIT_CONFIG_DEFAULT as a Pascal function)
will need these.

## Expected

Export an alias the same way as its target: resolve the chain to a constant
expression, or to the enum constant.

## Acceptance

All five names in the repro print 7, 8, 1, 2. Then
`./build.sh qemu-prog test/abi_import_check.pas` in ~/museum_landkaart/async
prints `ABI checked=70 mismatches=0` without -dALIAS_WORKAROUND. Today it fails to
compile on exactly those 8; with the workaround the result is 70/70.
