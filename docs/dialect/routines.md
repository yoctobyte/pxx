# Routines

Procedures and functions, `var`/`const`/value parameters, and `Result`/the
function-name return all behave as in FPC. This page covers the PXX extras and
limits.

## Overloads

Multiple routines may share a name, resolved by argument types. The `overload;`
directive is **optional by default**; `--strict-overload` (or
`{$STRICT_OVERLOAD ON}`) requires it on every variant, `--permissive-overload`
relaxes it again.

## Operator overloading

`operator` definitions for class/record operands, mirroring FPC:

```pascal
operator + (a, b: TVec): TVec;
begin
  Result.X := a.X + b.X;
  Result.Y := a.Y + b.Y;
end;
```

Record-valued operator results assign into both explicit and inferred targets.
Operands wider than a machine word should be passed `const` (see
[Types](types.md) on by-value record truncation).

## Auto-typed and inline `var` (PXX extras)

Two non-FPC conveniences, **both on by default**:

- **Inline `var`** — a `var` statement may appear anywhere in a block, not only
  in the routine's top `var` section. It is scoped to its block.
- **Auto-typed `var`** — a `var` with an initializer infers its type; spell the
  type as `auto` or omit it. Inference requires an initializer.

```pascal
begin
  var i := 0;              { inferred Integer, declared inline }
  var name: auto := 'Pi';  { explicit auto keyword }
  var x: Double := 3.14;   { inline, explicit type }
  for i := 1 to 10 do …
end;
```

Disable with `--no-auto-var` / `--no-lazy-var` (or `-fno-auto-var` /
`-fno-lazy-var`).

## Generics

Explicit **named specialization** only — there is no call-site sugar like
`Max<Integer>(a, b)`:

```pascal
generic function Max<T>(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;
specialize Max<Integer> as MaxInt;          { top-level form }

type
  generic TList<T> = class
    FItems: array of T;
    procedure Add(v: T);
  end;
  TIntList = specialize TList<Integer>;      { type-section form }
specialize TList<AnsiString> as TStrList;    { top-level form }
```

## Directives on routines

A routine header may carry one or more directives after the signature's `;`,
each terminated by its own `;`:

```pascal
procedure Foo; inline;
function  Bar(x: Integer): Integer; overload; inline;
procedure Imp(v: Integer); cdecl; external 'libfoo.so' name 'imp';
```

| Directive | Status | Meaning |
| --- | --- | --- |
| `overload` | effective | Same name, resolved by argument types. Optional unless `--strict-overload`. See above. |
| `external 'lib' [name 'sym']` | effective | Dynamically-linked import; symbol defaults to the routine name, `name` overrides it. |
| `forward` | effective | Declare now, define later in the same scope. |
| `assembler` | effective | Body is inline machine code — see [Inline assembly](inline-asm.md). |
| `generator` | effective | Coroutine that `yield`s values — see [Generators](generators.md). |
| `async` | effective | Marks an `await`-legalising routine (see *Async* below). |
| `stackful` | effective (default) | Heap-coroutine backend for `generator`/`async`. Documentary when it is already the default. |
| `stackless` | effective | State-machine backend; only valid together with `generator`/`async`. |
| `iram` | effective (ESP) | Place the routine's code in IRAM (`.iram1.text`) — ESP32 only. See [Targets](targets.md). |
| `inline` | accepted, **no-op** | Reserved; the routine is **not** inlined today (planned: [feature-inline-routines](../progress/backlog/feature-inline-routines.md)). |
| `register` | accepted, **no-op** | See *Calling conventions* below. |
| `cdecl` | accepted, **no-op** | See *Calling conventions* below. |
| `interrupt` | parsed, **not implemented** | Raw hardware-vector codegen errors out (see *Interrupt handlers*). |

Unlisted convention directives (`stdcall`, `safecall`, `pascal`,
`nostackframe`, …) are **not** recognised and are a syntax error. Use the
ones above.

### Calling conventions

PXX uses **one** internal calling convention for all Pascal-to-Pascal calls, so
`register` and the Pascal `pascal` convention have nothing to select — they are
accepted as no-ops for source compatibility. Cross-language calls do not need a
convention directive either: a routine marked `external` is called with the
**target's platform C ABI automatically** (SysV on x86-64 / AArch64, the
respective 32-bit ABIs on i386 / ARM32 / RISC-V / Xtensa). `cdecl` is therefore
redundant — kept only so FPC/Delphi headers parse unchanged.

### Async

`async` is a **non-viral** marker: it does not change the return type and does
not force callers to be async. It legalises `await E` inside the body. Under the
**stackful** backend (the default) `async`/`await` are *documentary* — `await E`
evaluates exactly as `E` (the coroutine runs to its next suspension on the same
heap stack). The **stackless** backend (`async; stackless;`) transforms the body
into a state machine. As with generators, bare `async` uses the stackful backend
today; automatic stackful/stackless selection is planned, so force the backend
explicitly when it matters. See [Generators](generators.md) for the backend
trade-offs (stackful = x86-64 only; stackless = every target, tiny-RAM friendly).

### Interrupt handlers

`interrupt` is **embedded-only by design**. Installing a routine as a raw
hardware interrupt vector requires owning the vector table and the CPU's
privileged state — available on a bare-metal target (ESP32), **not** on a hosted
OS (i386/x86-64/AArch64/ARM32 user code runs unprivileged; an ISR there would
mean a kernel module, out of scope). The directive currently **parses but its
raw-vector codegen is unimplemented** (full register save/restore + return-from
-interrupt), so it errors with a clear message. For an IDF-registered ISR on
ESP32 today, write an ordinary routine marked `iram;` and register it through the
IDF API. `interrupt` implies `iram` (a handler must be IRAM-resident).
