/* SPDX-License-Identifier: 0BSD
   QuickJS-ng unity runner (feature-c-corpus-quickjs): include the engine core
   as one translation unit (the zlib/tcc bring-up method), plus a minimal
   embedder main that evaluates a JS source string and prints the result.

   Fetch the candidate first: tools/install_lib_candidates.sh quickjs
   Build (oracle):  gcc -O1 -Ilibrary_candidates/quickjs test/quickjs/runner.c -lm -lpthread
   Build (pxx):     pascal26 -Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/quickjs \
                      test/quickjs/runner.c /tmp/qjs_runner

   First bar (ticket): evaluate `1+2` -> prints 3. */

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
