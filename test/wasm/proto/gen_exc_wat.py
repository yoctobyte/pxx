#!/usr/bin/env python3
"""Hand-compile test/wasm/proto/exc_proto.pas to WAT under the Phase 5 v1 scheme.

This is a PROTOTYPE, not a backend. It exists to answer one question the plan
flags as unproven: does nested try/except/finally compose with a br_table
dispatch loop, with exceptions threaded as a pending flag?

The scheme under test, in full:
  * every function body is a flat list of basic blocks, entered through one
    `loop $dispatch` + `br_table` on an i32 `$label` local;
  * a `raise` is: set the two globals, set $label to the STATICALLY known
    innermost enclosing landing pad of this function, br $dispatch;
  * after every call, check $exc_pending and jump to that same pad;
  * a `finally` is a block whose successor is a per-finally i32 local
    ($fincont) — the continuation label. That local is what lets one copy of
    the finally body serve the normal path, the unwind path (and, in the real
    backend, break/continue/Exit as well);
  * an `except` is a block that saves $exc_val into a frame slot and clears
    $exc_pending; a bare `raise;` re-arms both from that slot;
  * frame slots live in linear memory off a $sp global (the shadow stack);
    $sp is restored at the single epilogue every path brs to.
"""

def dispatch(name, params, result, locals_, blocks, prologue, epilogue,
             framesize):
    n = len(blocks)
    out = []
    sig = "".join(" (param $%s i32)" % p for p in params)
    if result:
        sig += " (result i32)"
    out.append("(func $%s%s" % (name, sig))
    for l in locals_:
        out.append("  (local $%s i32)" % l)
    out.append("  ;; prologue: claim %d bytes of shadow stack" % framesize)
    out.append("  (global.set $sp (i32.sub (global.get $sp) (i32.const %d)))"
               % framesize)
    out.append("  (local.set $fp (global.get $sp))")
    for line in prologue:
        out.append("  " + line)
    out.append("  (block $exit")
    out.append("   (loop $dispatch")
    out.append("    (block $Btrap")
    for i in range(n - 1, -1, -1):
        out.append("    " + " " * (n - 1 - i) + "(block $B%d" % i)
    table = " ".join("$B%d" % i for i in range(n)) + " $Btrap"
    out.append("    " + " " * n + "(br_table %s (local.get $label))" % table)
    for i in range(n):
        pad = "    " + " " * (n - 1 - i)
        out.append(pad + ")  ;; --- B%d ---" % i)
        for line in blocks[i]:
            out.append(pad + " " + line)
    out.append("    )  ;; --- $Btrap: unreachable label value ---")
    out.append("    (unreachable)")
    out.append("   )")
    out.append("  )")
    out.append("  ;; epilogue: the ONE place $sp is restored — normal and")
    out.append("  ;; unwind exits both br here")
    out.append("  (global.set $sp (i32.add (global.get $sp) (i32.const %d)))"
               % framesize)
    for line in epilogue:
        out.append("  " + line)
    out.append(")")
    return "\n".join(out)


def goto(n):
    return ["(local.set $label (i32.const %d))" % n, "(br $dispatch)"]


# ---------------------------------------------------------------- $Thrower
# Result := 0; if n > 2 then raise (100+n); Result := n*10;
# No try frame in this function, so `raise` unwinds straight out.
thrower = dispatch(
    "Thrower", ["n"], True, ["label", "fp"],
    [
        # B0
        ["(i32.store (local.get $fp) (i32.const 0))",
         "(if (i32.gt_s (local.get $n) (i32.const 2))",
         "  (then (local.set $label (i32.const 1)))",
         "  (else (local.set $label (i32.const 2))))",
         "(br $dispatch)"],
        # B1 — raise, no enclosing pad in this frame: arm and unwind-return
        ["(global.set $exc_pending (i32.const 1))",
         "(global.set $exc_val (i32.add (i32.const 100) (local.get $n)))",
         "(i32.store (local.get $fp) (i32.const 0))  ;; dummy result",
         "(br $exit)"],
        # B2
        ["(i32.store (local.get $fp) (i32.mul (local.get $n) (i32.const 10)))",
         "(br $exit)"],
    ],
    [], ["(i32.load (local.get $fp))"], 16)

# ----------------------------------------------------------------- $Middle
# try Result := Thrower(n); writeln(1000+Result); finally writeln(2000+n); end
# No handler here: the finally's unwind continuation is the frame's exit.
middle = dispatch(
    "Middle", ["n"], True, ["label", "fp", "fincont"],
    [
        # B0 — try body
        ["(i32.store (local.get $fp) (call $Thrower (local.get $n)))",
         "(if (global.get $exc_pending)",
         "  (then (local.set $fincont (i32.const 3)))   ;; finally -> unwind",
         "  (else",
         "    (call $print (i32.add (i32.const 1000) (i32.load (local.get $fp))))",
         "    (local.set $fincont (i32.const 2))))      ;; finally -> normal",
         "(local.set $label (i32.const 1))",
         "(br $dispatch)"],
        # B1 — finally body, one copy, two successors
        ["(call $print (i32.add (i32.const 2000) (local.get $n)))",
         "(local.set $label (local.get $fincont))",
         "(br $dispatch)"],
        # B2 — normal exit
        ["(br $exit)"],
        # B3 — unwind exit: $exc_pending is still armed, result is garbage
        ["(br $exit)"],
    ],
    [], ["(i32.load (local.get $fp))"], 16)

# -------------------------------------------------------------- $EarlyExit
# Result := -1; try if n=1 then Exit(42); Result := 7 finally writeln(8000+n)
# end; Result := 99;
#   The point: Exit-through-finally is not a new mechanism. It is the SAME
#   finally block with a third continuation-label value — the one that brs to
#   the epilogue instead of to the code after the try.
early = dispatch(
    "EarlyExit", ["n"], True, ["label", "fp", "fincE"],
    [
        # B0 — try body
        ["(i32.store (local.get $fp) (i32.const -1))",
         "(if (i32.eq (local.get $n) (i32.const 1))",
         "  (then",
         "    (i32.store (local.get $fp) (i32.const 42))  ;; Exit(42)",
         "    (local.set $fincE (i32.const 3)))           ;; finally -> return",
         "  (else",
         "    (i32.store (local.get $fp) (i32.const 7))",
         "    (local.set $fincE (i32.const 2))))          ;; finally -> after try",
         "(local.set $label (i32.const 1))",
         "(br $dispatch)"],
        # B1 — the one finally body, now with THREE possible successors
        ["(call $print (i32.add (i32.const 8000) (local.get $n)))",
         "(local.set $label (local.get $fincE))",
         "(br $dispatch)"],
        # B2 — after the try
        ["(i32.store (local.get $fp) (i32.const 99))",
         "(br $exit)"],
        # B3 — the Exit() continuation
        ["(br $exit)"],
    ],
    [], ["(i32.load (local.get $fp))"], 16)

# ------------------------------------------------------------------- $main
# fp+0 = i ; fp+4 = saved exception for the case-D inner handler
I = "(local.get $fp)"
SAVED = "(i32.add (local.get $fp) (i32.const 4))"
TMP   = "(i32.add (local.get $fp) (i32.const 8))"

main_blocks = [
    # 0  A: try body — call Middle(1), post-call check.
    #    NOTE the ordering: the result lands in a frame slot FIRST, and the
    #    pending check dominates every use of it. Printing the call result
    #    inline would print garbage on the unwind path.
    ["(i32.store %s (call $Middle (i32.const 1)))" % TMP,
     "(if (global.get $exc_pending)",
     "  (then (local.set $fincA (i32.const 3)))   ;; -> A's handler",
     "  (else",
     "    (call $print (i32.load %s))" % TMP,
     "    (local.set $fincA (i32.const 2))))      ;; -> after A",
     "(local.set $label (i32.const 1))",
     "(br $dispatch)"],
    # 1  A: finally
    ["(call $print (i32.const 3001))",
     "(local.set $label (local.get $fincA))",
     "(br $dispatch)"] ,
    # 2  A: normal continuation
    goto(4),
    # 3  A: except handler
    ["(global.set $exc_pending (i32.const 0))",
     "(call $print (i32.const 4001))"] + goto(4),
    # 4  B: try body — call Middle(5), same discipline
    ["(i32.store %s (call $Middle (i32.const 5)))" % TMP,
     "(if (global.get $exc_pending)",
     "  (then (local.set $fincB (i32.const 7)))",
     "  (else",
     "    (call $print (i32.load %s))" % TMP,
     "    (local.set $fincB (i32.const 6))))",
     "(local.set $label (i32.const 5))",
     "(br $dispatch)"],
    # 5  B: finally
    ["(call $print (i32.const 3002))",
     "(local.set $label (local.get $fincB))",
     "(br $dispatch)"],
    # 6  B: normal continuation
    goto(8),
    # 7  B: except handler
    ["(global.set $exc_pending (i32.const 0))",
     "(call $print (i32.const 4002))"] + goto(8),
    # 8  C: i := 0
    ["(i32.store %s (i32.const 0))" % I] + goto(9),
    # 9  C: loop head
    ["(if (i32.lt_s (i32.load %s) (i32.const 4))" % I,
     "  (then (local.set $label (i32.const 10)))",
     "  (else (local.set $label (i32.const 14))))",
     "(br $dispatch)"],
    # 10 C: loop body / try body
    ["(i32.store %s (i32.add (i32.load %s) (i32.const 1)))" % (I, I),
     "(call $print (i32.add (i32.const 5000) (i32.load %s)))" % I,
     "(if (i32.eq (i32.load %s) (i32.const 2))" % I,
     "  (then",
     "    (global.set $exc_pending (i32.const 1))",
     "    (global.set $exc_val (i32.const 777))",
     "    (local.set $fincC (i32.const 12)))   ;; finally -> unwind",
     "  (else (local.set $fincC (i32.const 13))))  ;; finally -> loop head",
     "(local.set $label (i32.const 11))",
     "(br $dispatch)"],
    # 11 C: finally
    ["(call $print (i32.add (i32.const 6000) (i32.load %s)))" % I,
     "(local.set $label (local.get $fincC))",
     "(br $dispatch)"],
    # 12 C: unwind continuation -> C's handler
    goto(15),
    # 13 C: normal continuation -> loop head
    goto(9),
    # 14 C: normal loop exit
    goto(16),
    # 15 C: except handler
    ["(global.set $exc_pending (i32.const 0))",
     "(call $print (i32.const 4003))"] + goto(16),
    # 16 D: inner try body — raise 888, innermost pad is the inner handler
    ["(global.set $exc_pending (i32.const 1))",
     "(global.set $exc_val (i32.const 888))"] + goto(17),
    # 17 D: inner except handler, then a bare `raise;`
    ["(i32.store %s (global.get $exc_val))  ;; save current exception" % SAVED,
     "(global.set $exc_pending (i32.const 0))",
     "(call $print (i32.const 7001))",
     "(global.set $exc_pending (i32.const 1))       ;; re-raise",
     "(global.set $exc_val (i32.load %s))" % SAVED] + goto(18),
    # 18 D: outer except handler
    ["(global.set $exc_pending (i32.const 0))",
     "(call $print (i32.const 7002))"] + goto(19),
    # 19 E: i := 0
    ["(i32.store %s (i32.const 0))" % I] + goto(20),
    # 20 E: loop head
    ["(if (i32.lt_s (i32.load %s) (i32.const 5))" % I,
     "  (then (local.set $label (i32.const 21)))",
     "  (else (local.set $label (i32.const 25))))",
     "(br $dispatch)"],
    # 21 E: loop body / try body — `break` is just another continuation value
    ["(i32.store %s (i32.add (i32.load %s) (i32.const 1)))" % (I, I),
     "(if (i32.eq (i32.load %s) (i32.const 3))" % I,
     "  (then (local.set $fincE2 (i32.const 24)))   ;; finally -> break",
     "  (else (local.set $fincE2 (i32.const 23))))  ;; finally -> loop head",
     "(local.set $label (i32.const 22))",
     "(br $dispatch)"],
    # 22 E: finally
    ["(call $print (i32.add (i32.const 8500) (i32.load %s)))" % I,
     "(local.set $label (local.get $fincE2))",
     "(br $dispatch)"],
    # 23 E: normal continuation -> loop head
    goto(20),
    # 24 E: break continuation -> after the loop
    goto(25),
    # 25 E: writeln(EarlyExit(1)) — post-call check kept even though this
    #    callee provably cannot raise; block 27 is main's unhandled path,
    #    which is what a frame with no enclosing try jumps to.
    ["(i32.store %s (call $EarlyExit (i32.const 1)))" % TMP,
     "(if (global.get $exc_pending)",
     "  (then (local.set $label (i32.const 27)))",
     "  (else",
     "    (call $print (i32.load %s))" % TMP,
     "    (local.set $label (i32.const 26))))",
     "(br $dispatch)"],
    # 26 E: writeln(EarlyExit(0))
    ["(i32.store %s (call $EarlyExit (i32.const 0)))" % TMP,
     "(if (global.get $exc_pending)",
     "  (then (local.set $label (i32.const 27)))",
     "  (else",
     "    (call $print (i32.load %s))" % TMP,
     "    (local.set $label (i32.const 28))))",
     "(br $dispatch)"],
    # 27 unhandled exception escaping main — never taken here
    ["(call $print (i32.const -1))",
     "(unreachable)"],
    # 28 tail
    ["(call $print (i32.const 9999))",
     "(br $exit)"],
]

main = dispatch("main", [], False,
                ["label", "fp", "fincA", "fincB", "fincC", "fincE2"],
                main_blocks, [], [], 16)

MODULE = """(module
  (import "env" "print" (func $print (param i32)))
  (memory (export "memory") 1)
  (global $sp (mut i32) (i32.const 65536))
  (global $exc_pending (mut i32) (i32.const 0))
  (global $exc_val (mut i32) (i32.const 0))

%s

%s

%s
  (export "main" (func $main))
)
"""

body = "\n\n".join(
    "\n".join("  " + l for l in f.split("\n"))
    for f in (thrower, middle, early, main))
print(MODULE % tuple(body.split("\n\n\n")) if False else
      "(module\n"
      '  (import "env" "print" (func $print (param i32)))\n'
      "  (memory (export \"memory\") 1)\n"
      "  (global $sp (mut i32) (i32.const 65536))\n"
      "  (global $exc_pending (mut i32) (i32.const 0))\n"
      "  (global $exc_val (mut i32) (i32.const 0))\n\n"
      + "\n\n".join("\n".join("  " + l for l in f.split("\n"))
                    for f in (thrower, middle, early, main))
      + '\n\n  (export "main" (func $main))\n'
      + '  (export "sp" (global $sp))\n'
      + '  (export "exc_pending" (global $exc_pending))\n)')
