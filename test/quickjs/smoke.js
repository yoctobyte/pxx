/* Curated quickjs smoke (make test-quickjs): one script, prints one line per
   case; stdout is byte-compared against smoke.expected, itself verified
   byte-identical to a gcc-built runner's output. Exercises the classes the
   bring-up fixed: JSValue struct returns through fn-pointer tables, exact
   number->string, closures, prototypes, GC pressure, JSON, regex, spread.
   Deliberately avoids cbrt/log/pow/exp — crtl transcendental 1-ulp accuracy
   is tracked separately; sqrt/sin/tan are exact. */
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
out.join('\n');
