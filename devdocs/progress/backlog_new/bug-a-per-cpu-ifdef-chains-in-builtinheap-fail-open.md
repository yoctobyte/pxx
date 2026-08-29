---
track: A
prio: 60
type: bug
blocked-by: []
summary: "The per-CPU {$ifdef} chains in compiler/builtin/builtinheap.pas have no terminal {$else}, so a target with no arm gets whatever the pre-chain default was — and for PXXSysOpenRO and PXXSysLseek there is no default at all: Result is NEVER ASSIGNED. Both are guarded only by {$ifndef PXX_ESP} and have arms for x86-64/i386/arm32/aarch64 only, so on HOSTED RISCV32 and on wasm32 they compile and return the return slot's leftover contents. PXXStrLoadFile then does `if fd < 0 then Exit` on that garbage and, if it happens to be non-negative, calls PXXAlloc(size + ...) with an equally garbage size. Four instances of the same generator shape in this one file; the systemic fix is a terminal else that fails LOUD, not four more arms."
status: new
owner: ""
---

# The per-CPU `{$ifdef}` chains in `builtinheap.pas` fail open

- **Type:** bug (RTL / builtin) — **Track A** (`compiler/builtin/**`).
- **Filed:** 2026-08-28 by the wasm32 lane, from an audit the coordinator asked
  for after `bug-a-pxxsyswrite-has-no-wasm32-arm` turned out to be an instance
  of a shape rather than a one-off.
- **Not a wasm ticket.** wasm32 is how it was noticed; **hosted riscv32** is the
  shipping target that hits it today.

## The shape

Every per-target syscall wrapper in this file is written as a run of
`{$ifdef CPU_x}` blocks with **no terminal `{$else}`**. Adding a target means
adding an arm; forgetting to means the routine silently does nothing, or worse.
There is no place for the compiler to say "this target has no arm."

Four instances in this one file:

| routine | arms | pre-chain default | what an armless target gets |
| --- | --- | --- | --- |
| `PXXSysWrite` (1537) | 5 + wasm32 | `Result := 0` | "wrote nothing, no error" — **fixed**, see `bug-a-pxxsyswrite-has-no-wasm32-arm` |
| `HeapMmap` (681) | 5 | `Result := 0` | a heap that bumps from **address 0** — filed, `bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero` |
| **`PXXSysOpenRO` (1861)** | **4** | **none** | `Result` **never assigned** |
| **`PXXSysLseek` (1877)** | **4** | **none** | `Result` **never assigned** |

The first two at least return a *defined* wrong value. The last two do not.

## The two that are worse, and who they hit

```pascal
function PXXSysOpenRO(path: Pointer): Int64;
begin
{$ifdef CPUX86_64}  Result := __pxxrawsyscall(2,  Int64(path), 0, 0);    {$endif}
{$ifdef CPU_I386}   Result := __pxxrawsyscall(5,  Int64(path), 0, 0);    {$endif}
{$ifdef CPU_ARM32}  Result := __pxxrawsyscall(5,  Int64(path), 0, 0);    {$endif}
{$ifdef CPUAARCH64} Result := __pxxrawsyscall(56, -100, Int64(path), 0, 0); {$endif}
end;
```

`PXXSysLseek` is the same four arms. Both sit inside `{$ifndef PXX_ESP}` —
**ESP is excluded deliberately and says so in the header comment; nothing
excludes riscv32 or wasm32.** Meanwhile `PXXSysRead` and `PXXSysWrite`, twenty
lines earlier and in the same group, *do* carry `CPU_RISCV32` arms (63 / 64,
"hosted linux (qemu-user)"). So the drift is visible in the file: riscv32 was
added to read and write and not to open and lseek.

The caller makes the consequence concrete (`PXXStrLoadFile`, 1912):

```pascal
  fd := PXXSysOpenRO(path);
  if fd < 0 then Exit;                     { garbage may well be >= 0 }
  size := PXXSysLseek(fd, 0, 2);           { garbage }
  ...
  base := Int64(PXXAlloc(size + PXX_HDR_SIZE + 1, 8));   { garbage-sized alloc }
```

So on hosted riscv32, `LoadFile` on a target with no `open` does not fail — it
proceeds on an uninitialised fd and allocates an arbitrary amount of memory.

## The fix that is NOT four more arms

Adding `CPU_RISCV32` to both closes today's instance and leaves the generator
running: the next target repeats it, exactly as wasm32 just did twice.

Give every chain a terminal `{$else}` that fails **loud**:

```pascal
{$ifdef CPUAARCH64} ... {$endif}
{$if not (defined(CPUX86_64) or defined(CPU_I386) or defined(CPU_ARM32)
          or defined(CPUAARCH64) or defined(CPU_RISCV32))}
  {$error PXXSysOpenRO has no arm for this target}
{$endif}
```

A compile-time refusal is the right failure here for the same reason the wasm32
backend records an unlowered body rather than skipping it: a target that cannot
do something must say so, not return a plausible value. If a target genuinely
should be a no-op (ESP has no filesystem), that is an explicit arm saying
`Result := -1`, not an absence.

Whether `{$error}` / `{$if defined(...)}` are available in this dialect is the
first thing to check; if not, an explicit `{$else} Result := -1; {$endif}` per
chain is the fallback, and at least the value is defined and negative.

## Related

- Same generator shape, different file: the Track P ticket filed 2026-08-27 for
  a `{$ifdef}` chain of 34 arms with no final `else` silently ignoring a
  compiler directive. Two files, one defect class, one week.
- `bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero` (p70)
  is the instance with the largest blast radius and stays open on its own.
