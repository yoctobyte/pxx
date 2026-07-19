/* Duktape curated JS smoke — feature-c-corpus-duktape.
 *
 * Evals a fixed list of JS snippets and prints each result via String(...).
 * The expected stdout lives in test/duktape/duk_smoke.expected; the Makefile
 * byte-compares and requires exit 42. Covers the classes duktape exercises
 * that nothing else in the C corpus does: IEEE-754 double formatting and
 * string<->number round-trips (the b30ccf88/6b16cb85 bug family), NaN/Inf,
 * double modulo, mark/sweep GC pressure, closures, prototypes, JSON, regex,
 * deep recursion.
 */
/* Unity build: crtl units first (libc-free headers/impls), then the duktape
 * amalgamation, then the driver — the cjson/chess runner shape. Define
 * DUK_SMOKE_HOSTED to build against a real libc instead (the gcc oracle
 * cross-check: `gcc -DDUK_SMOKE_HOSTED -I<duktape>/src duk_smoke.c -lm`). */
#ifndef DUK_SMOKE_HOSTED
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "math.c"
#include "locale.c"
#include "time.c"
#else
#include <stdio.h>
#endif
#include "duktape.c"

static const char *cases[] = {
    "1 + 2 * 3",
    "0.5",
    "3.0",
    "1.5 + 1.0",
    "0.1 + 0.2",
    "1 / 3",
    "Math.sqrt(2)",
    "Math.floor(2.7)",
    "7.5 % 2",
    "0 / 0",
    "1 / 0",
    "-1 / 0",
    "String(1e21)",
    "(123.456).toFixed(2)",
    "parseFloat('3.14159') * 2",
    "'abc' + 'def' + 123",
    "'hello world'.toUpperCase().split(' ').reverse().join('-')",
    "[1,2,3,4,5].map(function(x){return x*x;}).join(',')",
    "(function(){var a=[];for(var i=0;i<10;i++)a.push(i);return a.reduce(function(s,x){return s+x;},0);})()",
    "(function(){function mk(n){return function(){return n*2;};} var f=mk(21); return f();})()",
    "JSON.stringify({a:1,b:[true,null,'x'],c:{d:2.5}})",
    "JSON.parse('{\"x\": 42, \"y\": [1, 2.5]}').y[1]",
    "'The Quick Brown Fox'.replace(/quick/i, 'slow')",
    "/(\\d+)-(\\d+)/.exec('17-42')[2]",
    "(function fib(n){return n<2?n:fib(n-1)+fib(n-2);})(20)",
    "(function(){var s=0;for(var i=0;i<2000;i++){var o={v:i,arr:[i,i+1],s:'x'+i};s+=o.arr[1];}return s;})()",
    "(function(){function A(x){this.x=x;} A.prototype.get=function(){return this.x+1;}; return new A(41).get();})()",
    "typeof undefined + ',' + typeof null + ',' + typeof 1.5 + ',' + typeof 'x'",
};

int main(void) {
    duk_context *ctx = duk_create_heap_default();
    unsigned i;
    if (!ctx) { printf("heap creation failed\n"); return 1; }
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        if (duk_peval_string(ctx, cases[i]) != 0) {
            printf("%02u: ERROR %s\n", i, duk_safe_to_string(ctx, -1));
        } else {
            printf("%02u: %s\n", i, duk_safe_to_string(ctx, -1));
        }
        duk_pop(ctx);
    }
    /* force a full GC pass after the workload — mark/sweep must not crash */
    duk_gc(ctx, 0);
    duk_gc(ctx, 0);
    duk_destroy_heap(ctx);
    printf("done\n");
    return 42;
}
