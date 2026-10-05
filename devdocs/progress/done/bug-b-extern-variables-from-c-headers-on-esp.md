---
track: B
prio: 45
type: bug
blocked-by: []
summary: "Two gaps stop a Pascal unit from using a C global declared `extern` in an ESP-IDF header: (1) `uses idf;` does not import `extern T x;` at all (`undefined variable`), even on host; (2) Pascal's own `var x: T; cvar; external;` is refused for riscv32/xtensa objects (ObjRefuseEspDataImports: 'the reference would relocate into this object's own .bss'). WIFI_INIT_CONFIG_DEFAULT() needs two of these (g_wifi_osi_funcs, g_wifi_default_wpa_crypto_funcs). Measured 2026-10-05, pxx 2e07225c3c."
status: done
owner: ""
---

# Extern variables from C headers on ESP

- **Type:** bug / missing feature (C header import, ESP object writer). **Track B.**
- **Filed:** 2026-10-05 from `~/museum_landkaart/async`, the app's header
  import port (`uses idf;` → src/idf.h). Every other IDF ingredient now
  comes from the headers.

## Repro 1: the header import drops extern variables (host, no ESP needed)

```sh
cat > exth.h <<'EOF'
typedef struct { int a; int b; } pair_t;
extern pair_t g_pair;
extern const pair_t g_cpair;
extern int g_int;
EOF
cat > t.pas <<'EOF'
program t;
uses exth;
var p: ^pair_t;
begin
  p := @g_pair;
  writeln(p^.a, ' ', g_cpair.b, ' ', g_int);
end.
EOF
pascal26 -I. -Fu. t.pas t
# error: undefined variable (g_pair)   ... (g_cpair)
```

`pair_t` imports fine; only the variables are missing.

## Repro 2: Pascal's own external variable is refused on ESP

In a unit compiled with `--target=riscv32 --platform=esp --emit-obj`:

```pascal
var g_wifi_osi_funcs: wifi_osi_funcs_t; cvar; external;
```

```
error: --emit-obj: an imported variable (g_wifi_osi_funcs) is not supported
for xtensa/riscv32 objects: the reference would relocate into this object's
own .bss and read zero. Export an accessor from the defining side instead
```

On ESP the defining side is a prebuilt IDF blob (libnet80211.a,
libwpa_supplicant), so the suggested accessor would need a C shim in the
app. That is exactly what header import should make unnecessary.

## What the app does meanwhile

The same trick as before the port: `procedure g_wifi_osi_funcs; external;`
is declared purely to take its link-time address, and is cast to the
header's real types (`PWpaCryptoFuncs(@g_wifi_default_wpa_crypto_funcs)^`).
This works because a text UND symbol relocates correctly. That makes it
likely that (2) only needs a data UND symbol with the same R_RISCV_*
relocations that a call/address-of already gets.
test/abi_import_check.pas compares the resulting wifi_init_config_t
byte for byte with gcc's layout: 0 differences.

## Acceptance

- Repro 1 compiles and prints `1 4 5` when linked with the C definitions.
- In an ESP object, `@g_wifi_osi_funcs` and a by-value read of
  `g_wifi_default_wpa_crypto_funcs` (both from `uses idf;`, no Pascal
  redeclaration) link into firmware and resolve to IDF's symbols. The app's
  test/abi_import_check.pas then passes with the two routine stand-ins
  deleted from src/lkwifi.pas.

## Log

- 2026-10-05: filed from museum_landkaart/async.
