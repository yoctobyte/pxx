# Rust Frontend Notes

**Status:** planned. Rust is not yet an implemented frontend. This document
covers the design approach, specifically memory management, for when it lands.

---

## The Borrow Checker: What It Is And Why It Matters

Rust's borrow checker is a genuinely brilliant piece of compiler engineering.
Its job is to prove, at compile time, that every piece of memory has exactly
one owner at any given moment, and that no reference outlives what it points
to. If the proof holds, the compiler guarantees: no use-after-free, no
dangling pointers, no data races — and zero runtime cost for any of it.

This is what makes Rust work as a language. The entire design — ownership,
moves, borrows, lifetimes — is built around giving the compiler enough
information to construct that proof. When it succeeds, you get C-speed code
with memory safety baked in at compile time, no garbage collector needed.

It is a hard problem. Implementing a correct borrow checker is a significant
undertaking in its own right.

---

## What PXX Does Instead

PXX will not implement the borrow checker for the Rust frontend.

Instead, heap allocations are managed by **reference counting**: every heap
object carries a counter. When a reference is copied, the counter increments.
When a reference goes out of scope, the counter decrements. When the counter
reaches zero, the memory is freed. The last one to let go frees it.

This is not a new idea. Pascal has managed strings this way since the early
1990s. It works.

The tradeoff is straightforward:

| | Borrow checker | Reference counting |
|--|----------------|--------------------|
| When | Compile time | Runtime |
| Memory overhead | None | One counter per heap object |
| CPU overhead | None | Increment/decrement on free; negligible in practice |
| Catches bugs | Yes — compile error | No — runs, behaves correctly |
| Cycles | Impossible (ownership is a DAG) | Can leak (A → B → A) |
| Implementation cost | Very high | Low |

Reference counting trades a small amount of memory per allocation and a
counter decrement at free time for not needing a proof system in the compiler.
The free-path overhead is real but negligible — a single decrement and
conditional branch. For most
real Rust programs, the behavior is identical. The programs that rely on the
borrow checker to *reject* unsafe code won't get that rejection — but they
will still compile and run correctly if the code is in fact safe.

The borrow checker is the compiler doing hard puzzle-solving so the runtime
doesn't have to. Reference counting skips the puzzle and pays a small runtime
price instead. Both reach the same destination: no garbage collector, memory
freed deterministically.

---

## What This Means In Practice

- Rust programs that use standard ownership patterns compile and run correctly.
- Programs with shared ownership (`Rc<T>`, `Arc<T>`) map naturally — PXX
  applies the same refcount mechanism universally.
- Cycles between heap objects can leak. This mirrors the known limitation of
  `Rc<T>` in Rust itself (which is why Rust also has `Weak<T>`). It is a
  known, bounded tradeoff.
- The borrow checker's *safety guarantees* are not provided. PXX compiles
  Rust syntax to native code; it does not certify memory safety.
- Lifetime annotations are parsed and accepted but not enforced.

---

## Syntax Scope

Rust syntax is not dramatically harder to parse than Pascal. The grammar is
explicit and well-documented. The hard parts of Rust are semantic, not
syntactic — and the hardest semantic part (borrow checking) is the one we are
deliberately not implementing.

A useful Rust subset is achievable without implementing a proof system.

---

## Other Quirks Worth Noting

**Traits**
Rust's trait system covers both static dispatch (generics + monomorphization,
same as our generic specialization) and dynamic dispatch (`dyn Trait`, a vtable
pointer). Both are implementable; monomorphization we already do for Pascal
generics. `dyn Trait` maps to a fat pointer (data ptr + vtable ptr).

**Enums with data (algebraic data types)**
Rust enums can carry payloads — `Option<T>`, `Result<T, E>`, and user-defined
variants. These are tagged unions: a discriminant integer plus a union of
variant payloads. Straightforward to lay out in memory. `match` exhaustiveness
checking (a compile-time proof) will not be enforced, but the syntax and
dispatch are fully implementable.

**Closures**
`Fn`, `FnMut`, `FnOnce` — closures capture their environment. Compiled as a
struct (the captured variables) plus a function pointer that takes the struct
as a hidden first argument. Not novel; Pascal supports nested procedures with
similar closure-like captures.

**Macros**
`macro_rules!` (declarative macros) is a pattern-matching macro system baked
into the language and used pervasively. Non-trivial to implement fully.
Procedural macros (compiler plugins) are out of scope entirely. Initial
frontend will handle common built-in macros (`println!`, `vec!`, `assert!`,
`panic!`) as intrinsics and defer full `macro_rules!` support.

**The `?` operator**
`expr?` desugars to: if result is `Err`, return it early; otherwise unwrap.
Syntactic sugar — straightforward to handle in codegen.

**No implicit numeric conversions**
Rust refuses to silently coerce `i32` to `i64` or similar. This is
load-bearing in real Rust code (programs rely on the compiler catching mixed
types). Worth enforcing in the frontend since skipping it produces wrong
codegen, not just missing safety.

**`async`/`await`**
Transforms functions into state machines at compile time. Complex and
pervasive in modern Rust. Out of scope for the initial frontend.

**String types**
Rust has `str` (unsized slice), `&str` (borrowed reference to string data),
and `String` (heap-owned, growable). `&str` maps cleanly to a pointer + length
pair. `String` maps to our heap allocation with refcount. The distinction
between them is more a parsing/type-checking concern than a codegen one.

**Shadowing**
Rust allows re-declaring a variable with the same name in the same scope
(`let x = 1; let x = x + 1;`). Different from Pascal. Requires the symbol
table to support shadowing within a scope rather than rejecting it.
