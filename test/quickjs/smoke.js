/* Curated quickjs smoke (make test-quickjs): one script, prints one line per
   case; stdout is byte-compared against smoke.expected, itself verified
   byte-identical to a gcc-built runner's output. Exercises the classes the
   bring-up fixed: JSValue struct returns through fn-pointer tables, exact
   number->string, closures, prototypes, GC pressure, JSON, regex, spread.
   Full Math-surface block at the bottom (feature-crtl-libm-correctly-rounded-
   transcendentals): crtl's exp/log/pow/cbrt/log2/log10/expm1/log1p/trig/
   inverse-trig/hyperbolics/hypot are correctly rounded (dd kernels, b377-
   b385). Runtime glibc itself misrounds some arguments (e.g. cbrt(27) ->
   3.0000000000000004, acosh(2), atanh(0.5)); the values here are chosen
   where the gcc oracle agrees with correct rounding. */
const out = [];
out.push(1 + 2 * 3);
out.push(0.5, 3.0, 1.5 + 1.0, 0.1 + 0.2, 1 / 3);
out.push(Math.sqrt(2), Math.sin(1), Math.tan(0.5), Math.floor(2.7), 7.5 % 2);
out.push(0 / 0, 1 / 0, -1 / 0, 1e21, (123.456).toFixed(2), (1.005).toFixed(2));
out.push('abc' + 'def' + 123);
out.push('hello world'.toUpperCase().split(' ').reverse().join('-'));
out.push([1, 2, 3, 4, 5].map(x => x * x).join(','));
out.push([...Array(10).keys()].reduce((a, b) => a + b, 0));
out.push((function mk(n) { return () => n * 2; })(21)());
out.push(JSON.stringify({ a: 1, b: [true, null, 'x'], c: { d: 2.5 } }));
out.push(JSON.parse('{"x": 42, "y": [1, 2.5]}').y[1]);
out.push('The Quick Brown Fox'.replace(/quick/i, 'slow'));
out.push(/(\d+)-(\d+)/.exec('17-42')[2]);
out.push((function fib(n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); })(22));
out.push((() => { let s = 0; for (let i = 0; i < 3000; i++) { const o = { v: i, a: [i, i + 1], s: 'x' + i }; s += o.a[1]; } return s; })());
out.push((class A { constructor(x) { this.x = x; } get() { return this.x + 1; } }, new (class B { constructor(x) { this.x = x; } get() { return this.x + 1; } })(41).get()));
out.push(typeof undefined + ',' + typeof null + ',' + typeof 1.5 + ',' + typeof 'x');
out.push([3, 1, 2].sort().join(''), 'a,b,,c'.split(',').length);
/* full Math surface — correctly-rounded crtl libm (b377-b385) */
out.push(Math.exp(1), Math.exp(-3.5), Math.log(10), Math.log(0.25), Math.pow(2, 0.5), Math.pow(10, -3), Math.pow(1.5, 60.5));
out.push(Math.cbrt(8), Math.cbrt(-8), Math.cbrt(3));
out.push(Math.log2(10), Math.log2(1024), Math.log10(2), Math.log10(1e6));
out.push(Math.expm1(0.5), Math.expm1(-1e-5), Math.log1p(0.5), Math.log1p(1e-5));
out.push(Math.sinh(1), Math.cosh(1), Math.tanh(0.5), Math.asinh(1), Math.acosh(3), Math.atanh(0.75));
out.push(Math.sin(1), Math.cos(1), Math.tan(0.5), Math.sin(1e6), Math.tan(54321.123));
out.push(Math.asin(0.5), Math.acos(0.5), Math.atan(1), Math.atan2(1, 2), Math.atan2(-3, -4));
out.push(Math.hypot(3, 4), Math.hypot(1, 1), Math.fround(1.1), Math.fround(-2.7));
out.push(Math.sign(-3), Math.clz32(7), Math.imul(7, 3));
out.push(Math.abs(-2.5), Math.floor(-2.5), Math.ceil(-2.5), Math.round(-2.5), Math.trunc(-2.5), Math.min(1, -2, 3), Math.max(1, -2, 3));
out.join('\n');
