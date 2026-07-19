/* SPDX-License-Identifier: 0BSD
   QuickJS-ng unity runner (feature-c-corpus-quickjs): include the engine core
   as one translation unit (the zlib/tcc bring-up method), plus a minimal
   embedder main that evaluates a JS source string and prints the result.

   Fetch the candidate first: tools/install_lib_candidates.sh quickjs
   Build (oracle):  gcc -O1 -Ilibrary_candidates/quickjs test/quickjs/runner.c -lm -lpthread
   Build (pxx):     pascal26 -Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/quickjs \
                      test/quickjs/runner.c /tmp/qjs_runner

   First bar (ticket): evaluate `1+2` -> prints 3. */

/* Portable single-thread engine profile: EMSCRIPTEN selects switch dispatch
   (no computed goto), no pthread/js_once, no C11 atomics — the plain-C build
   quickjs-ng already maintains. The gcc oracle builds this same file, so both
   compilers get the identical configuration. */
#define EMSCRIPTEN 1
/* 32-bit bignum limbs: __TINYC__ steers libbf.h away from the 64-bit-limb
   config whose dlimb_t is unsigned __int128 (pxx has no int128). Upstream
   maintains this exact profile for tcc; its only other effect (quickjs.c
   atomics guard) is already off under EMSCRIPTEN. */
#define __TINYC__ 1

#include "cutils.c"
#include "libunicode.c"
#include "libregexp.c"
#include "libbf.c"
#include "quickjs.c"

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    JSRuntime *rt;
    JSContext *ctx;
    JSValue v;
    const char *src = "1+2";
    const char *s;

    if (argc > 1)
        src = argv[1];

    rt = JS_NewRuntime();
    if (!rt) { printf("FAIL: no runtime\n"); return 1; }
    ctx = JS_NewContext(rt);
    if (!ctx) { printf("FAIL: no context\n"); return 1; }

    v = JS_Eval(ctx, src, strlen(src), "<input>", JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(v)) {
        JSValue e = JS_GetException(ctx);
        s = JS_ToCString(ctx, e);
        printf("EXCEPTION: %s\n", s ? s : "?");
        return 2;
    }
    s = JS_ToCString(ctx, v);
    printf("%s\n", s ? s : "?");
    return 0;
}
