
## 2026-07-08 (fable-c) — root cause pinned; parked as feature-sized
Confirmed the ROOT CAUSE: `typedef float v4[4];` registers v4 as a plain
scalar `float` — ParseCTypedef reads the name then skips the `[4]` (falls to
the `while <> ';'` skip). So `v4 r` is a scalar (a brace init then errors
"expected C expression"), and `v4 rows[2]` never becomes 2-D. Nothing to do
with the init walker (which is ready — the multidim-ordinal-global fix,
b203/0db36672, already drives N-D ordinal arrays end to end).

The fix is ARRAY-TYPEDEF SUPPORT, a feature spanning the shared declarator
path (self-host risk), not a bounded init patch:
1. Store the typedef's inherent array shape (a `CTypedefArrLen` / NDims/DimSpan
   parallel to CTypedefProcSig) — capture the `[N]..` after the name in
   ParseCTypedef.
2. ParseCDeclType outputs that shape (a `CTypeArrLen`/dims) when a declarator's
   base is an array typedef.
3. The local + global array decl paths FOLD the typedef's dims UNDER any
   declarator-applied dims: `v4 r` -> [4]; `v4 rows[2]` -> [2][4] (set
   SymArrNDims/DimSpan), then the existing walker inits it (single + array,
   local + global).
Parked (claim released) — needs a focused declarator-path session. Unblocks
cglm (`vec4 csCoords[8]`, vec4 = float[4]).
