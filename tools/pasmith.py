#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""pasmith -- Csmith-style random Object Pascal program generator.

See devdocs/progress/backlog/feature-pasmith-pascal-program-generator.md.

Emits a random, WELL-DEFINED, TERMINATING Object Pascal program whose entire
observable output is a single checksum line. Same seed -> byte-identical
program. Intended to be compiled by both pxx and FPC (and by pxx for several
targets / -O levels); any disagreement on the checksum is a bug in one of
them (see the ticket's triage table -- FPC is an oracle, not ground truth).

The four invariants, stolen from Csmith, are the whole reason this works:

  1. UB-free BY CONSTRUCTION -- never "usually". Division and mod are routed
     through guarded helpers, shift counts are masked to the operand width,
     every variable is initialised at declaration, and arithmetic runs under
     {$Q-}{$R-} where wraparound is the defined behaviour both compilers
     implement. A generator that can emit undefined behaviour produces
     divergences that are nobody's bug, and dies of false positives.
  2. ONE checksum out -- all live state is folded into a single qword and
     printed once. Not intermediate prints: it makes diffing trivial and
     survives shrinking.
  3. SEEDED and reproducible -- the seed is written into the file header.
  4. ALWAYS TERMINATES -- `for` loops over constant bounds only, and the call
     graph is a DAG (function i may only call function j>i), so there is no
     recursion and no unbounded loop to generate. (tools/fuzz.sh learned this
     one the hard way: its first run hung when a mutation turned a
     terminating loop infinite.)

Usage:
    tools/pasmith.py --seed 42                # program to stdout
    tools/pasmith.py --seed 42 -o out.pas
"""

import argparse
import random
import sys

# --- type model ------------------------------------------------------------
# Only ordinal scalars in v1 (the ticket's v1 rung). Records/sets/ansistring/
# classes are v2+ and are where the interesting bugs are expected to be -- but
# v1 is what proves the harness is trustworthy enough to believe them.


class Ty:
    def __init__(self, name, bits, signed, kind="int"):
        self.name = name          # Pascal type name
        self.bits = bits
        self.signed = signed
        self.kind = kind          # int | bool | char

    def __repr__(self):
        return self.name


INT_TYPES = [
    Ty("shortint", 8, True),
    Ty("byte", 8, False),
    Ty("smallint", 16, True),
    Ty("word", 16, False),
    Ty("longint", 32, True),
    Ty("longword", 32, False),
    Ty("int64", 64, True),
    Ty("qword", 64, False),
]
BOOL = Ty("boolean", 8, False, "bool")
CHAR = Ty("char", 8, False, "char")
ALL_TYPES = INT_TYPES + [BOOL, CHAR]

BIN_INT_OPS = ["+", "-", "*", "and", "or", "xor"]
CMP_OPS = ["=", "<>", "<", "<=", ">", ">="]
BOOL_OPS = ["and", "or", "xor"]


def lit_for(ty, rnd):
    """A literal that always fits `ty` -- never relies on range checking."""
    if ty.kind == "bool":
        return rnd.choice(["true", "false"])
    if ty.kind == "char":
        return "chr(%d)" % rnd.randint(32, 126)
    if ty.signed:
        lo, hi = -(1 << (ty.bits - 1)), (1 << (ty.bits - 1)) - 1
    else:
        lo, hi = 0, (1 << ty.bits) - 1
    # Bias toward the edges: boundary values are where assumptions break.
    if rnd.random() < 0.35:
        v = rnd.choice([lo, hi, 0, 1, -1 if ty.signed else 0, lo + 1, hi - 1])
        v = max(lo, min(hi, v))
    else:
        v = rnd.randint(max(lo, -1000), min(hi, 1000))
    # int64/qword literals near the limits need no suffix in FPC/pxx, but a
    # bare negative literal as a typecast argument parses fine parenthesised.
    return "(%d)" % v if v < 0 else str(v)


class Gen:
    def __init__(self, seed, nvars=8, nfuncs=3, stmts=12, depth=3, trace=False,
                 nclasses=0, nobjs=3, nstrs=0):
        self.rnd = random.Random(seed)
        self.seed = seed
        # OOP + ansistring rungs. These are the POINT of a Pascal smith rather
        # than just running Csmith: a C generator cannot reach a vtable, an
        # inheritance chain, a ctor/dtor ordering, or a refcounted copy-on-write
        # string, and those are where the assumptions live.
        self.nclasses = nclasses
        self.nobjs = nobjs
        self.nstrs = nstrs
        self.classes = []      # [{name, base, fields, methods}]
        self.in_method = False  # guards against o.Name recursion inside a method
        self.strs = []         # ansistring globals
        # --trace: emit the running checksum after EVERY statement instead of
        # only at exit. Diffing two oracles' traces localises a divergence to
        # the exact statement, on a program of ANY size -- which is why this
        # tool has no shrinker. See localize() in pasmith_run.py.
        self.trace = trace
        self.ckpt = 0
        self.nvars = nvars
        self.nfuncs = nfuncs
        self.nstmts = stmts
        self.maxdepth = depth
        self.globals = []      # (name, Ty)
        self.funcs = []        # dicts: name, ret Ty, params [(name,Ty,byref)]
        self.loopvars = []     # names of for-loop control vars in scope
        # Loop control vars must be LOCAL to whatever body is being generated.
        # They used to be globals shared by main and every function -- so a
        # loop in main calling a function that also looped would have its
        # control variable clobbered underneath it. Modifying a `for` control
        # var inside its own loop is UNDEFINED in Pascal, and the two compilers
        # duly disagreed: FPC re-reads the counter from memory and spins
        # forever, pxx keeps it in a register and terminates. A divergence
        # neither compiler owns -- exactly the false positive that makes a
        # fuzzer worthless. Per-body prefix keeps them distinct.
        self.lvprefix = "li"
        self.tmpc = 0

    # -- expressions --------------------------------------------------------
    def vars_of(self, ty, scope):
        return [n for (n, t) in scope if t.name == ty.name]

    def leaf(self, ty, scope):
        """A leaf of type `ty` -- a VARIABLE for integer types, never a literal.

        This is load-bearing, not a style choice. An all-constant subexpression
        such as `qword(231) shl 63` gets CONSTANT-FOLDED at compile time, and
        FPC rejects an overflow during folding as a hard *error* -- {$Q-}
        governs runtime wraparound, not constant evaluation. Feeding arithmetic
        from variables instead makes the whole class unreachable: a variable
        cannot be folded, so no expression this generator emits can overflow at
        compile time. (Every integer type is guaranteed to have a variable in
        scope -- see gen()/gen_func(), which seed one of each.)

        Literals survive only where they cannot overflow: initialisers, `for`
        bounds, case labels, and shift masks.
        """
        cands = self.vars_of(ty, scope)
        if cands:
            return self.rnd.choice(cands)
        return lit_for(ty, self.rnd)   # bool/char only; cannot overflow

    def expr(self, ty, scope, depth):
        """A well-defined expression of exactly type `ty`.

        Every arithmetic result is explicitly typecast back to `ty`, so
        truncation is the *specified* behaviour rather than an accident of
        promotion rules -- this is what keeps mixed-width arithmetic
        comparable across two compilers.
        """
        rnd = self.rnd
        cands = self.vars_of(ty, scope)

        if depth <= 0 or rnd.random() < 0.30:
            return self.leaf(ty, scope)

        if ty.kind == "bool":
            k = rnd.random()
            if k < 0.45:
                # comparison of two ints of a common type
                it = rnd.choice(INT_TYPES)
                a = self.expr(it, scope, depth - 1)
                b = self.expr(it, scope, depth - 1)
                return "(%s %s %s)" % (a, rnd.choice(CMP_OPS), b)
            if k < 0.75:
                a = self.expr(BOOL, scope, depth - 1)
                b = self.expr(BOOL, scope, depth - 1)
                return "(%s %s %s)" % (a, rnd.choice(BOOL_OPS), b)
            if k < 0.85:
                return "(not %s)" % self.expr(BOOL, scope, depth - 1)
            return self.leaf(ty, scope)

        if ty.kind == "char":
            # chr() of a masked byte: always in range, never a range error.
            e = self.expr(INT_TYPES[4], scope, depth - 1)   # longint
            return "chr(longint(%s) and 127)" % e

        # --- integer types
        k = rnd.random()
        f = self.callable_func(ty, scope, depth)
        if f is not None and k < 0.12:
            return f
        if k < 0.55:
            op = rnd.choice(BIN_INT_OPS)
            a = self.expr(ty, scope, depth - 1)
            b = self.expr(ty, scope, depth - 1)
            return "%s(%s %s %s)" % (ty.name, a, op, b)
        if k < 0.68:
            # guarded div/mod -- the classic UB source, routed through helpers
            # that are total functions (b=0 and the signed MIN div -1 overflow
            # are both folded away). Never emit a bare `div`.
            fn = rnd.choice(["SafeDiv", "SafeMod"])
            a = self.expr(ty, scope, depth - 1)
            b = self.expr(ty, scope, depth - 1)
            return "%s(%s(%s), %s(%s))" % (fn + suffix_for(ty), ty.name, a,
                                           ty.name, b)
        if k < 0.78:
            # shift, count masked to the operand width: never >= bits, which
            # is where C and Pascal alike stop promising anything.
            a = self.expr(ty, scope, depth - 1)
            b = self.expr(ty, scope, depth - 1)
            op = rnd.choice(["shl", "shr"])
            return "%s(%s(%s) %s (%s(%s) and %d))" % (
                ty.name, ty.name, a, op, ty.name, b, ty.bits - 1)
        if k < 0.84 and ty.signed:
            return "%s(-%s)" % (ty.name, self.expr(ty, scope, depth - 1))
        if k < 0.90:
            return "%s(not %s)" % (ty.name, self.expr(ty, scope, depth - 1))
        if k < 0.96:
            # cross-type conversion: read a var of another type, cast in.
            ot = rnd.choice(ALL_TYPES)
            src = self.expr(ot, scope, depth - 1)
            if ot.kind in ("bool", "char"):
                src = "ord(%s)" % src
            return "%s(%s)" % (ty.name, src)
        return self.leaf(ty, scope)

    def callable_func(self, ty, scope, depth):
        opts = [f for f in self.funcs if f["ret"].name == ty.name]
        if not opts:
            return None
        f = self.rnd.choice(opts)
        args = [self.expr(p[1], scope, depth - 1) for p in f["params"]]
        return "%s(%s)" % (f["name"], ", ".join(args))

    # -- statements ---------------------------------------------------------
    def stmt(self, scope, depth, ind, assignable):
        rnd = self.rnd
        pad = "  " * ind
        k = rnd.random()

        if depth <= 0 or k < 0.42:
            if not assignable:
                return ["%sMix(0);" % pad]
            name, ty = rnd.choice(assignable)
            return ["%s%s := %s;" % (pad, name, self.expr(ty, scope, self.maxdepth))]

        if k < 0.58:
            cond = self.expr(BOOL, scope, 2)
            out = ["%sif %s then" % (pad, cond), "%sbegin" % pad]
            out += self.block(scope, depth - 1, ind + 1, assignable)
            out += ["%send" % pad]
            if rnd.random() < 0.5:
                out += ["%selse" % pad, "%sbegin" % pad]
                out += self.block(scope, depth - 1, ind + 1, assignable)
                out += ["%send" % pad]
            out[-1] += ";"
            return out

        if k < 0.74:
            # for over CONSTANT bounds -- termination by construction. The
            # control var is read-only inside (assigning to it is illegal in
            # FPC) and, per the standard, undefined AFTER the loop, so it goes
            # out of scope the moment the loop closes: never checksummed.
            lo = rnd.randint(0, 3)
            hi = lo + rnd.randint(0, 4)
            lv = "%s%d" % (self.lvprefix, len(self.loopvars))
            if len(self.loopvars) >= 3:
                name, ty = rnd.choice(assignable)
                return ["%s%s := %s;" % (pad, name, self.expr(ty, scope, 2))]
            self.loopvars.append(lv)
            inner = scope + [(lv, INT_TYPES[4])]     # longint, readable only
            out = ["%sfor %s := %d to %d do" % (pad, lv, lo, hi), "%sbegin" % pad]
            out += self.block(inner, depth - 1, ind + 1, assignable)
            out += ["%send;" % pad]
            self.loopvars.pop()
            return out

        if k < 0.88:
            sel = self.expr(INT_TYPES[4], scope, 2)
            out = ["%scase longint(%s) and 3 of" % (pad, sel)]
            for c in range(rnd.randint(1, 3)):
                out += ["%s  %d: begin" % (pad, c)]
                out += self.block(scope, depth - 1, ind + 2, assignable)
                out += ["%s  end;" % pad]
            out += ["%selse" % pad]
            out += self.block(scope, depth - 1, ind + 1, assignable)
            out += ["%send;" % pad]
            return out

        if k < 0.94 and self.classes:
            o = self.pick_obj()
            kind = rnd.random()
            if kind < 0.5:
                # virtual dispatch through a base-typed reference
                return ["%sMix(%s.Calc(longint(%s)));"
                        % (pad, o, self.expr(INT_TYPES[4], scope, 2))]
            if kind < 0.8:
                return ["%sMixStr(%s.Name);" % (pad, o)]
            # write through a field: mutating object state between virtual calls
            c = self.classes[0]
            fn, ft = c["fields"][0]
            return ["%s%s.%s := %s(%s);"
                    % (pad, o, fn, ft.name, self.expr(ft, scope, 2))]

        if k < 0.97 and self.strs:
            name, _ = rnd.choice(self.strs)
            if rnd.random() < 0.6:
                return ["%s%s := %s;" % (pad, name, self.str_expr(scope, 2))]
            return ["%sMixStr(%s);" % (pad, self.str_expr(scope, 2))]

        # fold a live value into the checksum mid-stream: makes the output
        # sensitive to control flow, not just to final state.
        ty = rnd.choice(INT_TYPES)
        return ["%sMix(int64(%s));" % (pad, self.expr(ty, scope, 2))]

    def block(self, scope, depth, ind, assignable):
        out = []
        for _ in range(self.rnd.randint(1, 3)):
            out += self.stmt(scope, depth, ind, assignable)
        return out

    # -- OOP ----------------------------------------------------------------
    def str_expr(self, scope, depth):
        """A well-defined ansistring expression.

        Every operation here is total: concat always works, Length always
        works, and Copy is defined for out-of-range indices (it returns what is
        actually there). Indices are still kept in range so that a divergence
        means a real bug rather than an argument about Copy's clamping -- but
        Copy's clamping IS worth testing, so index bases are derived from live
        values rather than constants.
        """
        rnd = self.rnd
        cands = [n for (n, t) in scope if t.kind == "str"]
        if depth <= 0 or not cands or rnd.random() < 0.25:
            if cands and rnd.random() < 0.5:
                return rnd.choice(cands)
            return "'%s'" % "".join(rnd.choice("abcdefgh") for _ in range(rnd.randint(0, 4)))
        k = rnd.random()
        if k < 0.40:
            return "(%s + %s)" % (self.str_expr(scope, depth - 1),
                                  self.str_expr(scope, depth - 1))
        if k < 0.60:
            # Copy with LIVE (not constant) index/len: exercises the refcount /
            # copy-on-write path and the clamping rules together.
            s = self.str_expr(scope, depth - 1)
            i = self.expr(INT_TYPES[4], scope, 1)
            n = self.expr(INT_TYPES[4], scope, 1)
            return "Copy(%s, 1 + (longint(%s) and 7), 1 + (longint(%s) and 7))" % (s, i, n)
        if k < 0.75 and self.classes and not self.in_method:
            # NEVER inside a method body: Name calling o0.Name would recurse
            # forever (the objects are globals, so a method can see them). That
            # would break the terminates-by-construction invariant -- the whole
            # reason no generated program can hang.
            o = self.pick_obj()
            if o:
                return "%s.Name" % o
        if k < 0.88:
            e = self.expr(INT_TYPES[4], scope, 1)
            return "(%s + Chr(65 + (longint(%s) and 25)))" % (
                self.str_expr(scope, depth - 1), e)
        return rnd.choice(cands)

    def pick_obj(self):
        return "o%d" % self.rnd.randrange(self.nobjs) if self.nobjs else None

    def gen_classes(self):
        """A chain of classes, each overriding its parent's virtuals.

        A CHAIN (not a flat set) on purpose: `inherited` up a deep chain is what
        actually exercises vtable construction and method resolution. Every
        virtual is overridden in every subclass and calls `inherited`, so one
        call through a base-typed reference walks the whole chain.

        Lifetime discipline, which is what keeps this UB-free: a ctor
        initialises EVERY field it declares (so no field is ever read
        uninitialised), the dtor is the only place an object is destroyed, and
        main frees each object exactly once and never touches it afterwards.
        """
        rnd = self.rnd
        L = ["type"]
        for i in range(self.nclasses):
            name = "TC%d" % i
            base = "TC%d" % (i - 1) if i > 0 else "TObject"
            fields = [("cf%d_%d" % (i, j), rnd.choice(INT_TYPES))
                      for j in range(rnd.randint(1, 3))]
            fields.append(("cs%d" % i, STR))
            self.classes.append({"name": name, "base": base, "fields": fields, "idx": i})
            L.append("  %s = class(%s)" % (name, base))
            for fn, ft in fields:
                L.append("    %s: %s;" % (fn, ft.name))
            virt = "virtual" if i == 0 else "override"
            L.append("    constructor Create(v: longint); %s;" % virt)
            L.append("    destructor Destroy; override;")
            L.append("    function Calc(a: longint): longint; %s;" % virt)
            L.append("    function Name: ansistring; %s;" % virt)
            L.append("  end;")
        L.append("")
        return L

    def gen_class_bodies(self):
        rnd = self.rnd
        L = []
        self.in_method = True
        for c in self.classes:
            i = c["idx"]
            # Fields are in scope in every method. `v` is the CONSTRUCTOR's
            # parameter and must not leak into Calc/Name -- each method gets
            # only its own parameters.
            fscope = [(f, t) for f, t in c["fields"]]

            L.append("constructor %s.Create(v: longint);" % c["name"])
            L.append("begin")
            # inherited FIRST: the base must be constructed before this class's
            # fields are touched. Getting this order wrong would be a generator
            # bug that reads as a compiler bug.
            L.append("  inherited Create(%s);" % (
                "v" if i > 0 else ""))
            for fn, ft in c["fields"]:
                if ft.kind == "str":
                    L.append("  %s := 'c%d';" % (fn, i))
                else:
                    L.append("  %s := %s(v + %s);" % (fn, ft.name, lit_for(ft, rnd)))
            L.append("end;")
            L.append("")

            # The destructor folds state into the checksum, so ctor/dtor ORDER
            # and dtor COUNT are observable: a missed or double destructor call,
            # or a chain walked in the wrong order, changes the output.
            L.append("destructor %s.Destroy;" % c["name"])
            L.append("begin")
            L.append("  Mix(%d);" % (1000 + i))
            L.append("  Mix(int64(%s));" % c["fields"][0][0])
            L.append("  inherited Destroy;")
            L.append("end;")
            L.append("")

            # Fields alone need not cover all 8 integer types, and leaf() must
            # always find a VARIABLE of the type it wants -- otherwise it falls
            # back to a literal and the compile-time-overflow class comes back.
            # So every method carries one local of each integer type.
            mloc = [("m%d" % j, t) for j, t in enumerate(INT_TYPES)]
            mdecl = ["var"] + ["  %s: %s;" % (n, t.name) for n, t in mloc]
            minit = ["  %s := %s(a);" % (n, t.name) for n, t in mloc]

            L.append("function %s.Calc(a: longint): longint;" % c["name"])
            L += mdecl
            L.append("begin")
            L += minit
            body_scope = fscope + mloc + [("a", INT_TYPES[4])]
            if i > 0:
                L.append("  Calc := longint(%s + inherited Calc(a));"
                         % self.expr(INT_TYPES[4], body_scope, 2))
            else:
                L.append("  Calc := longint(%s);" % self.expr(INT_TYPES[4], body_scope, 2))
            L.append("end;")
            L.append("")

            L.append("function %s.Name: ansistring;" % c["name"])
            L += mdecl
            L.append("begin")
            L += ["  %s := %s(%s);" % (n, t.name, lit_for(t, rnd)) for n, t in mloc]
            nscope = fscope + mloc
            if i > 0:
                L.append("  Name := (inherited Name) + %s;" % self.str_expr(nscope, 2))
            else:
                L.append("  Name := %s;" % self.str_expr(nscope, 2))
            L.append("end;")
            L.append("")
        self.in_method = False
        return L

    # -- whole program ------------------------------------------------------
    def gen(self):
        rnd = self.rnd
        # One global of EVERY type, first: leaf() needs a variable of each
        # integer type in scope to avoid ever emitting a foldable constant
        # expression (see leaf()). The extra --vars are random on top.
        for i, t in enumerate(ALL_TYPES):
            self.globals.append(("g%d" % i, t))
        for i in range(len(ALL_TYPES), len(ALL_TYPES) + self.nvars):
            self.globals.append(("g%d" % i, rnd.choice(ALL_TYPES)))

        L = []
        L.append("program pasmith_%d;" % self.seed)
        L.append("{ GENERATED by tools/pasmith.py -- seed %d. Do not edit." % self.seed)
        L.append("  Reproduce with: tools/pasmith.py --seed %d" % self.seed)
        # The generation parameters travel WITH the source: a divergence is
        # reproduced from the seed, so the seed alone must be enough to rebuild
        # the identical program (this is what makes a shrinker unnecessary).
        L.append("  gen-args: --vars %d --funcs %d --stmts %d --depth %d "
                 "--classes %d --objs %d --strs %d }"
                 % (self.nvars, self.nfuncs, self.nstmts, self.maxdepth,
                    self.nclasses, self.nobjs, self.nstrs))
        L.append("{$mode objfpc}")
        # Wraparound is the DEFINED behaviour we test; range/overflow checks
        # off means arithmetic is total, so there is no trap to diverge on.
        L.append("{$Q-}")
        L.append("{$R-}")
        L.append("")
        clsdecl = self.gen_classes() if self.nclasses else []
        L += clsdecl
        L.append("var")
        L.append("  cs: qword;")
        for n, t in self.globals:
            L.append("  %s: %s;" % (n, t.name))
        for i in range(self.nstrs):
            self.strs.append(("s%d" % i, STR))
            L.append("  s%d: ansistring;" % i)
        if self.nclasses:
            # Objects are declared as the BASE class but instantiated as random
            # derived ones -- so every method call below goes through the vtable
            # rather than being statically resolvable. A devirtualising optimiser
            # that gets this wrong shows up as an -O-level self-contradiction.
            for i in range(self.nobjs):
                L.append("  o%d: TC0;" % i)
        for lv in ["li0", "li1", "li2"]:
            L.append("  %s: longint;" % lv)
        L.append("")
        L.append("procedure Mix(v: int64);")
        L.append("begin")
        L.append("  cs := qword(cs * 1000003) xor qword(v);")
        L.append("end;")
        L.append("")
        L.append("procedure MixStr(const s: ansistring);")
        L.append("var i: longint;")
        L.append("begin")
        L.append("  Mix(Length(s));")
        L.append("  for i := 1 to Length(s) do Mix(ord(s[i]));")
        L.append("end;")
        L.append("")
        if self.trace:
            # A checkpoint: fold ALL live state and print it. One line per
            # statement, so a diff of two oracles' traces names the exact
            # statement at which they first disagreed. No source deletion, and
            # it works on a program of any size -- bigger is strictly better.
            L.append("procedure Snap;")
            L.append("var s: qword; i: longint;")
            L.append("begin")
            L.append("  s := cs;")
            for n, t in self.globals:
                cast = "ord(%s)" % n if t.kind in ("bool", "char") else "int64(%s)" % n
                L.append("  s := qword(s * 1000003) xor qword(%s);" % cast)
            for n, t in self.strs:
                # String state must be in the trace too, or a divergence in a
                # string statement would show a clean checkpoint and mislocate.
                L.append("  for i := 1 to Length(%s) do "
                         "s := qword(s * 31) xor qword(ord(%s[i]));" % (n, n))
            L.append("  writeln(s);")
            L.append("end;")
            L.append("")
        L += safe_helpers()
        L.append("")
        if self.nclasses:
            L += self.gen_class_bodies()

        # Functions, generated in reverse so function i can only call j>i:
        # the call graph is a DAG, hence no recursion, hence termination.
        for i in reversed(range(self.nfuncs)):
            L += self.gen_func(i)
            L.append("")

        L.append("begin")
        L.append("  cs := 0;")
        for n, t in self.globals:
            L.append("  %s := %s;" % (n, lit_for(t, rnd)))
        for n, t in self.strs:
            L.append("  %s := '%s';" % (n, "".join(
                rnd.choice("abcdefgh") for _ in range(rnd.randint(0, 5)))))
        for i in range(self.nclasses and self.nobjs):
            # Instantiate a RANDOM class from the chain into a base-typed slot.
            L.append("  o%d := TC%d.Create(%d);"
                     % (i, rnd.randrange(self.nclasses), rnd.randint(1, 50)))
        L.append("")
        body_scope = list(self.globals) + list(self.strs)
        for _ in range(self.nstmts):
            L += self.stmt(body_scope, self.maxdepth, 1, list(self.globals))
            if self.trace:
                self.ckpt += 1
                L.append("  Snap;   { checkpoint %d }" % self.ckpt)
        L.append("")
        L.append("  { fold ALL live state into one number: the sole output }")
        for n, t in self.globals:
            if t.kind in ("bool", "char"):
                L.append("  Mix(ord(%s));" % n)
            else:
                L.append("  Mix(int64(%s));" % n)
        for n, t in self.strs:
            L.append("  MixStr(%s);" % n)
        for i in range(self.nclasses and self.nobjs):
            # Free each object EXACTLY once and never touch it again. The
            # destructors fold into the checksum on their way out, so the dtor
            # chain (count and order) is part of the observed output -- a missed
            # or doubled destructor call changes the number.
            L.append("  o%d.Free;" % i)
        L.append("  writeln(cs);")
        L.append("end.")
        return "\n".join(L) + "\n"

    def gen_func(self, idx):
        rnd = self.rnd
        name = "f%d" % idx
        ret = rnd.choice(INT_TYPES)
        params = []
        for p in range(rnd.randint(1, 3)):
            params.append(("p%d" % p, rnd.choice(INT_TYPES), False))
        sig = "; ".join("%s: %s" % (p[0], p[1].name) for p in params)

        # Locals give the body somewhere to write. Globals are deliberately
        # NOT assignable inside functions: a function called from within an
        # expression could otherwise mutate a variable that same expression
        # also reads, and Pascal does not pin down the evaluation order of
        # the operands -- so the program's result would depend on a choice
        # the language leaves open. That is exactly the "legitimately allowed
        # to differ" trap that makes a fuzzer useless. Functions here are
        # pure: params + locals in, value out.
        # One local of every integer type, for the same reason as in gen(): a
        # function body must never be forced to fall back to a literal leaf.
        locs = [("v%d" % i, t) for i, t in enumerate(INT_TYPES)]
        scope = [(p[0], p[1]) for p in params] + locs

        lvp = "%s_li" % name        # loop vars local to THIS function
        L = ["function %s(%s): %s;" % (name, sig, ret.name)]
        L.append("var")
        for n, t in locs:
            L.append("  %s: %s;" % (n, t.name))
        for i in range(3):
            L.append("  %s%d: longint;" % (lvp, i))
        L.append("begin")
        for n, t in locs:
            L.append("  %s := %s;" % (n, lit_for(t, rnd)))
        saved, self.loopvars = self.loopvars, []
        savedp, self.lvprefix = self.lvprefix, lvp
        for _ in range(rnd.randint(1, 3)):
            L += self.stmt(scope, 2, 1, locs)
        self.loopvars = saved
        self.lvprefix = savedp
        L.append("  %s := %s;" % (name, self.expr(ret, scope, 2)))
        L.append("end;")

        # Registered only AFTER its body is generated, so its own body cannot
        # call it -- this is what makes the call graph acyclic.
        self.funcs.append({"name": name, "ret": ret, "params": params})
        return L


def suffix_for(ty):
    return "_" + ty.name


STR = Ty("ansistring", 0, False, "str")


def safe_helpers():
    """Total div/mod for every integer type.

    Two operands are folded away rather than guarded at the call site:
      b = 0   -- division by zero.
      b = -1  -- for signed types, MIN div -1 overflows the result type (the
                 one signed-division case that traps on x86 as well). Folding
                 it costs nothing and removes the entire class.
    Returning `a` for those cases keeps the helper total and deterministic.
    """
    out = []
    for t in INT_TYPES:
        guard = "(b = 0) or (b = -1)" if t.signed else "(b = 0)"
        for op, fn in (("div", "SafeDiv"), ("mod", "SafeMod")):
            out.append("function %s%s(a, b: %s): %s;" % (fn, suffix_for(t), t.name, t.name))
            out.append("begin")
            out.append("  if %s then %s%s := a else %s%s := a %s b;"
                       % (guard, fn, suffix_for(t), fn, suffix_for(t), op))
            out.append("end;")
    return out


def main():
    ap = argparse.ArgumentParser(description="random well-defined Object Pascal generator")
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("-o", "--output")
    ap.add_argument("--vars", type=int, default=8)
    ap.add_argument("--funcs", type=int, default=3)
    ap.add_argument("--stmts", type=int, default=12)
    ap.add_argument("--depth", type=int, default=3)
    ap.add_argument("--trace", action="store_true",
                    help="print the checksum after EVERY statement, not just at exit. "
                         "Diffing two oracles' traces localises a divergence to the "
                         "exact statement -- which is why this tool needs no shrinker.")
    ap.add_argument("--classes", type=int, default=0,
                    help="length of the inheritance chain (0 = no OOP). Every class "
                         "overrides its parent's virtuals and calls inherited, so one "
                         "call through a base-typed ref walks the whole chain.")
    ap.add_argument("--objs", type=int, default=3, help="base-typed object slots")
    ap.add_argument("--strs", type=int, default=0, help="ansistring globals")
    a = ap.parse_args()
    src = Gen(a.seed, a.vars, a.funcs, a.stmts, a.depth, a.trace,
              a.classes, a.objs, a.strs).gen()
    if a.output:
        with open(a.output, "w") as f:
            f.write(src)
    else:
        sys.stdout.write(src)
    return 0


if __name__ == "__main__":
    sys.exit(main())
