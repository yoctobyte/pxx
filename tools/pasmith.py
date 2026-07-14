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

# --- known-broken shapes we deliberately do NOT emit -----------------------
# A fuzzer's job is to find NEW bugs, not to keep re-finding filed ones. Both of
# these are FILED, with a five-line reproducer and a regression test in the
# acceptance criteria; generating them again would only re-trip a known ledger
# entry, which throttles fuzzing (see tstate/fuzz/README.md) and teaches nobody
# anything. Restore them -- they are one-line changes, marked below -- once the
# tickets land, because BOTH are then worth exercising properly:
#
#   * bug-pascal-shortstring-no-truncation-buffer-overrun
#       `string[N] := <longer than N>` overruns the buffer in pxx instead of
#       truncating. So every shortstring value this generator produces is clamped
#       to the declared capacity by construction (see short_expr) and truncation
#       is never exercised.
#   * compat-pascal-copy-of-char-literal
#       `Copy('a', i, n)` -- a one-character literal is typed CHAR, and pxx will
#       not promote it to a string the way FPC does. So string literals here are
#       never exactly one character long (see str_lit).
#   * bug-pascal-not-of-ord-uses-boolean-negation
#       `not ord(x)` computes a BOOLEAN not (xor 1) in pxx instead of a bitwise
#       complement, so a bare ord() leaf in an integer expression silently yields
#       the wrong number. Found by this generator's very first widened run. Bare
#       ord() reads are therefore wrapped in an explicit longint() cast, which is
#       where `not` behaves; drop the wrapper when the ticket lands (enum_reads).
NO_SHORTSTRING_TRUNCATION = False    # FIXED: fec98091 + 7716bd2a (truncating string[N] stores, all targets)
NO_ONE_CHAR_STRING_LITERAL = True    # compat-pascal-copy-of-char-literal
NO_BARE_NOT_ORD = False              # FIXED: not-ord bitwise + operand-width (bug-pascal-not-of-ord-uses-boolean-negation)


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


CHAIN = 3          # heap nodes in the linked list a ptrwalk walks


class Gen:
    def __init__(self, seed, nvars=8, nfuncs=3, stmts=12, depth=3, trace=False,
                 nclasses=0, nobjs=3, nstrs=0, nrecs=0, narrs=0, nenums=0,
                 nshorts=0, nexcepts=0, nmodeprocs=0, wide_p=0.45):
        self.rnd = random.Random(seed)
        self.seed = seed
        # The widened rungs (feature-pasmith-widen-grammar). Every one of them is a
        # bug class we have SHIPPED and the scalar grammar could not express:
        # records + forward pointers (b338), enum identity (b342), string[N] (b345),
        # exception hierarchies (b339), and the parameter modes / sets / arrays that
        # no C-shaped generator has an analogue for.
        self.nrecs = nrecs
        self.narrs = narrs
        self.nenums = nenums
        self.nshorts = nshorts
        self.nexcepts = nexcepts
        self.nmodeprocs = nmodeprocs
        self.wide_p = wide_p       # P(a statement is one of the widened kinds)
        self.recs = []
        self.arrs = []
        self.enums = []
        self.sets = []
        self.enumvars = []
        self.setvars = []
        self.shorts = []
        self.modeprocs = []
        self.arriter = "ai"        # for..in control var over an array of longint
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
        self.kind = "?"        # kind of the statement stmt() last returned
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
        # Side-effecting calls emitted in the CURRENT expression tree. Reset per
        # statement: Pascal specifies statement order, not evaluation order
        # within an expression. See expr().
        self.calls_in_expr = 0
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
        # AT MOST ONE side-effecting call per expression tree. Generated functions
        # fold into the checksum (they contain Mix statements), so they are NOT
        # pure -- and Pascal leaves argument/operand evaluation order
        # UNSPECIFIED. Two such calls in one operand pair, e.g.
        #
        #   SafeMod_qword(qword(not f1(g14)), qword(g7 and f0(g6, g6)))
        #
        # mix the same values in a DIFFERENT ORDER under pxx (left-to-right) and
        # FPC (right-to-left). Both compilers are correct; the checksums differ.
        # That is a divergence nobody owns -- the generator manufacturing false
        # signal, which is the one thing that makes a fuzzer worthless. It cost
        # ~3% of the corpus (bug-t-pasmith-order-dependent-programs).
        #
        # One call per expression keeps the sequence of Mix() calls determined by
        # STATEMENT order, which Pascal does specify -- while still exercising
        # side-effecting functions, which a blanket "make them pure" would lose.
        if k < 0.12 and self.calls_in_expr == 0:
            f = self.callable_func(ty, scope, depth)
            if f is not None:
                self.calls_in_expr += 1
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
        self.calls_in_expr = 0      # a new statement: a fresh evaluation-order scope

        if depth <= 0 or k < 0.42:
            if not assignable:
                return self.tagged("mix", ["%sMix(0);" % pad])
            name, ty = rnd.choice(assignable)
            return self.tagged("assign", [
                "%s%s := %s;" % (pad, name, self.expr(ty, scope, self.maxdepth))])

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
            return self.tagged("if", out)

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
            return self.tagged("for", out)

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
            return self.tagged("case", out)

        if k < 0.94 and self.classes:
            o = self.pick_obj()
            kind = rnd.random()
            if kind < 0.5:
                # virtual dispatch through a base-typed reference
                return self.tagged("virtcall", [
                    "%sMix(%s.Calc(longint(%s)));"
                    % (pad, o, self.expr(INT_TYPES[4], scope, 2))])
            if kind < 0.8:
                return self.tagged("virtstr", ["%sMixStr(%s.Name);" % (pad, o)])
            # write through a field: mutating object state between virtual calls
            c = self.classes[0]
            fn, ft = c["fields"][0]
            return self.tagged("field", [
                "%s%s.%s := %s(%s);"
                % (pad, o, fn, ft.name, self.expr(ft, scope, 2))])

        if k < 0.97 and self.strs:
            name, _ = rnd.choice(self.strs)
            if rnd.random() < 0.6:
                return self.tagged("strassign", [
                    "%s%s := %s;" % (pad, name, self.str_expr(scope, 2))])
            return self.tagged("strmix", [
                "%sMixStr(%s);" % (pad, self.str_expr(scope, 2))])

        wide = self.wide_stmt(scope, depth, ind, assignable)
        if wide is not None:
            return wide

        # fold a live value into the checksum mid-stream: makes the output
        # sensitive to control flow, not just to final state.
        ty = rnd.choice(INT_TYPES)
        return self.tagged("mix", ["%sMix(int64(%s));" % (pad, self.expr(ty, scope, 2))])

    def wide_stmt(self, scope, depth, ind, assignable):
        """The widened rungs: with / enum-case / set ops / for..in / exceptions /
        var-const-out calls / record copy / pointer walk / shortstring.

        Returns None when none of them is enabled or the dice say no, and the caller
        falls through to the scalar statement it always had.
        """
        rnd = self.rnd
        pad = "  " * ind
        opts = []
        if self.recs:
            opts += ["with", "reccopy", "ptrwalk"]
        if self.enumvars:
            opts += ["enumcase", "setop", "forinset"]
        if self.arrs:
            opts += ["forinarr"]
        if self.nexcepts:
            opts += ["raise", "tryfinally"]
        if self.modeprocs:
            opts += ["modecall"]
        if self.shorts:
            opts += ["shortassign"]
        if not opts or rnd.random() > self.wide_p:
            return None
        pick = rnd.choice(opts)

        if pick == "with":
            r = rnd.choice(self.recs)
            g = "r%dg" % r["idx"]
            out = ["%swith %s do" % (pad, g), "%sbegin" % pad]
            # Inside `with`, the fields are bare names. Field names are unique per
            # record type, so nothing is shadowed and every read is unambiguous.
            for fn, ft in r["fields"][:2]:
                if rnd.random() < 0.5:
                    out.append("%s  Mix(int64(%s));" % (pad, fn))
                else:
                    out.append("%s  %s := %s(%s);"
                               % (pad, fn, ft.name, self.expr(ft, scope, 2)))
            out.append("%send;" % pad)
            return self.tagged("with", out)

        if pick == "reccopy":
            # Whole-record assignment: the compiler must copy every field, the
            # nested record, the inline array and the inline string[N] -- a memcpy
            # whose size and alignment it computed itself.
            r = rnd.choice(self.recs)
            i = r["idx"]
            return self.tagged("reccopy", [
                "%sr%dg2 := r%dg;" % (pad, i, i),
                "%sMix(int64(r%dg2.%s));" % (pad, i, r["fields"][0][0]),
                "%sMix(int64(r%dg2.%s[1]));" % (pad, i, r["arr"][0])])

        if pick == "ptrwalk":
            # Walk the heap chain: CHAIN nodes, each visited once, then the pointer
            # lands on nil and is not dereferenced again. Bounded `for`, so it still
            # terminates by construction -- a `while p <> nil` would not.
            r = rnd.choice(self.recs)
            i = r["idx"]
            lv = "%s%d" % (self.lvprefix, len(self.loopvars))
            if len(self.loopvars) >= 3:
                return None
            self.loopvars.append(lv)
            out = ["%sw%d := h%d;" % (pad, i, i),
                   "%sfor %s := 0 to %d do" % (pad, lv, CHAIN - 1), "%sbegin" % pad,
                   "%s  Mix(int64(w%d^.%s));" % (pad, i, r["fields"][0][0]),
                   "%s  w%d := w%d^.next;" % (pad, i, i),
                   "%send;" % pad]
            self.loopvars.pop()
            return self.tagged("ptrwalk", out)

        if pick == "enumcase":
            e = rnd.choice(self.enumvars)
            et = e["ty"]
            out = ["%s%s := %s;" % (pad, e["var"], self.enum_expr(et, scope)),
                   "%scase %s of" % (pad, e["var"])]
            for j, v in enumerate(et["vals"]):
                out.append("%s  %s: Mix(%d);" % (pad, v, 700 + j))
            out.append("%send;" % pad)
            return self.tagged("enumcase", out)

        if pick == "setop":
            s = rnd.choice(self.setvars)
            et = s["enum"]
            op = rnd.choice(["+", "-", "*"])
            out = ["%s%s := %s %s [%s];"
                   % (pad, s["var"], s["var"], op, self.enum_expr(et, scope)),
                   "%sif %s in %s then Mix(801) else Mix(802);"
                   % (pad, self.enum_expr(et, scope), s["var"])]
            return self.tagged("setop", out)

        if pick == "forinset":
            s = rnd.choice(self.setvars)
            return self.tagged("forinset", [
                "%sfor %s in %s do Mix(900 + ord(%s));"
                % (pad, s["iter"], s["var"], s["iter"])])

        if pick == "forinarr":
            a = rnd.choice(self.arrs)
            return self.tagged("forinarr", [
                "%sfor %s in %s do Mix(int64(%s));"
                % (pad, self.arriter, a["name"], self.arriter)])

        if pick == "raise":
            # Raise a DERIVED class, catch it on a BASE one: `on E: EPas0` must
            # match an EPas2 down the chain. That is the exception-matching shape
            # (b339) -- and it is unreachable without a class hierarchy, which is
            # why the old grammar never went near it.
            n = self.nexcepts
            thrown = rnd.randrange(n)
            caught = rnd.randint(0, thrown)      # a base of what we throw: matches
            out = ["%stry" % pad,
                   "%s  if %s then raise EPas%d.Create('x%d');"
                   % (pad, self.expr(BOOL, scope, 2), thrown, thrown),
                   "%s  Mix(int64(%s));" % (pad, self.expr(INT_TYPES[4], scope, 2)),
                   "%sexcept" % pad,
                   "%s  on E: EPas%d do Mix(%d);" % (pad, caught, 500 + caught),
                   # The catch-all keeps the invariant: a generated program NEVER
                   # exits on an uncaught exception, whatever the handler above does.
                   "%s  on E: Exception do Mix(599);" % pad,
                   "%send;" % pad]
            return self.tagged("raise", out)

        if pick == "tryfinally":
            # The body never raises (nothing here does but a `raise` statement, and
            # this one does not emit one), so `finally` always runs exactly once and
            # nothing escapes. Order is what is being tested: the finally Mix must
            # land after the body's.
            out = ["%stry" % pad, "%sbegin" % pad]
            out += self.block(scope, depth - 1, ind + 1, assignable)
            out += ["%send;" % pad, "%sfinally" % pad,
                    "%s  Mix(%d);" % (pad, 3000 + rnd.randint(0, 9)),
                    "%send;" % pad]
            return self.tagged("tryfinally", out)

        if pick == "modecall":
            mp = rnd.choice(self.modeprocs)
            args, used = [], set()
            for pn, pt, mode in mp["params"]:
                if mode in ("var", "out"):
                    # var/out args must be VARIABLES, and must be DISTINCT from each
                    # other: passing the same variable as two writable parameters
                    # makes the result depend on the order the procedure happens to
                    # write them, which the language does not pin down. That is a
                    # divergence neither compiler owns -- the exact false-signal
                    # class that cost 3% of the corpus once already.
                    cands = [n for (n, t) in assignable
                             if t.name == pt.name and n not in used]
                    if not cands:
                        return None
                    a = rnd.choice(cands)
                    used.add(a)
                    args.append(a)
                else:
                    # A `const` arg is copied before the body runs, so it cannot
                    # alias a var arg -- but it must not CALL anything either, or the
                    # call's Mix() would interleave with the procedure's writes in an
                    # order the language leaves open. calls_in_expr blocks that.
                    self.calls_in_expr = 1
                    args.append("%s(%s)" % (pt.name, self.expr(pt, scope, 1)))
            self.calls_in_expr = 0
            return self.tagged("modecall",
                               ["%s%s(%s);" % (pad, mp["name"], ", ".join(args))])

        if pick == "shortassign":
            sh = rnd.choice(self.shorts)
            if rnd.random() < 0.5:
                return self.tagged("shortassign", [
                    "%s%s := %s;" % (pad, sh, self.short_expr(scope, 2))])
            return self.tagged("shortmix", ["%sMixStr(%s);" % (pad, sh)])

        return None

    def tagged(self, kind, lines):
        """Record the kind of the statement being returned, and hand it back.

        Set at RETURN, never at entry: a compound statement generates its nested
        children first, and those call stmt() recursively -- tagging on the way in
        would leave the innermost child's kind behind. The last write before the
        top-level call returns is the top-level statement's own kind, which is what
        a checkpoint names.

        The kind is what makes a finding DEDUPLICABLE: it travels into the trace
        checkpoint comment, so the driver can say "this divergence is at a `case`"
        and recognise the 500th instance of it as the same signature rather than
        as the 500th bug.
        """
        self.kind = kind
        return lines

    def block(self, scope, depth, ind, assignable):
        out = []
        for _ in range(self.rnd.randint(1, 3)):
            out += self.stmt(scope, depth, ind, assignable)
        return out

    # -- the Pascal-shaped rungs: records, pointers, enums, sets, arrays ------
    # Everything below exists because the bugs we actually SHIPPED lived here and
    # the old grammar could not reach them: forward pointer types resolving fields
    # at offset 0 (b338), enum type identity (b342), frozen string[N] (b345),
    # exception class matching across a hierarchy (b339). A generator that emits
    # only scalars, ifs and cases will re-find the same statement bug forever --
    # which is exactly what it did, 639 times.

    def gen_types(self):
        """Enums, sets, records (with FORWARD pointer types) and exception classes.

        The forward pointer is the point, not decoration: `PRk = ^TRk` written
        BEFORE TRk exists is the shape that resolved every field past a deref at
        offset 0 (b338). A generator that declares the record first would never see
        it.
        """
        rnd = self.rnd
        L = ["type"]
        for i in range(self.nenums):
            vals = ["e%d_%d" % (i, j) for j in range(rnd.randint(2, 5))]
            self.enums.append({"name": "TE%d" % i, "vals": vals})
            L.append("  TE%d = (%s);" % (i, ", ".join(vals)))
            # One set type per enum. `set of` is dialect surface C has no analogue
            # for, so Csmith-shaped fuzzing structurally cannot reach it.
            self.sets.append({"name": "TS%d" % i, "enum": self.enums[-1]})
            L.append("  TS%d = set of TE%d;" % (i, i))

        for i in range(self.nrecs):
            rec = {"name": "TR%d" % i, "ptr": "PR%d" % i, "idx": i}
            # FORWARD: the pointer names the record before the record exists.
            L.append("  PR%d = ^TR%d;" % (i, i))
            inner = [("r%di%d" % (i, j), rnd.choice(INT_TYPES))
                     for j in range(rnd.randint(1, 2))]
            rec["inner"] = inner
            rec["inner_name"] = "TR%dI" % i
            L.append("  TR%dI = %srecord" % (i, "packed " if rnd.random() < 0.4 else ""))
            for fn, ft in inner:
                L.append("    %s: %s;" % (fn, ft.name))
            L.append("  end;")
            fields = [("r%df%d" % (i, j), rnd.choice(INT_TYPES))
                      for j in range(rnd.randint(1, 3))]
            rec["fields"] = fields
            rec["arr"] = ("r%da" % i, 4, INT_TYPES[4])       # array[0..3] of longint
            rec["short"] = ("r%ds" % i, 8) if self.nshorts else None
            L.append("  TR%d = %srecord" % (i, "packed " if rnd.random() < 0.3 else ""))
            for fn, ft in fields:
                L.append("    %s: %s;" % (fn, ft.name))
            L.append("    r%dn: TR%dI;" % (i, i))
            L.append("    %s: array[0..%d] of %s;"
                     % (rec["arr"][0], rec["arr"][1] - 1, rec["arr"][2].name))
            if rec["short"]:
                L.append("    %s: string[%d];" % rec["short"])
            L.append("    next: PR%d;" % i)                  # the linked shape
            L.append("  end;")
            self.recs.append(rec)

        # An exception HIERARCHY, not a flat set: `on E: EPas1` must catch an
        # EPas2, which is the match-a-descendant shape (b339). Every raise is
        # caught by construction (the outermost handler is `on E: Exception`), so
        # a generated program still always exits 0.
        for i in range(self.nexcepts):
            base = "EPas%d" % (i - 1) if i > 0 else "Exception"
            L.append("  EPas%d = class(%s);" % (i, base))
        L.append("")
        return L if len(L) > 2 else []

    def enum_expr(self, e, scope):
        """A value of enum type `e`, ALWAYS in range.

        Casting an out-of-range ordinal to an enum is not defined, so the ordinal
        is folded modulo the number of values first. That keeps the whole class
        unreachable rather than merely unlikely -- the same discipline leaf() uses
        for constant folding.
        """
        n = len(e["vals"])
        if self.rnd.random() < 0.4:
            return self.rnd.choice(e["vals"])
        src = self.expr(INT_TYPES[4], scope, 1)
        # Mask to non-negative FIRST, then mod. Pascal's `mod` keeps the sign of the
        # dividend -- (-5) mod 3 is -2 -- so modding a possibly-negative value and
        # casting the result to an enum would produce an out-of-range ordinal, which
        # is not defined behaviour and would be a divergence nobody owns.
        return "%s((longint(%s) and 1073741823) mod %d)" % (e["name"], src, n)

    def short_expr(self, scope, depth):
        """A string[N] value that ALWAYS fits N, so truncation is never exercised.

        Not a style choice: pxx does not truncate an oversized shortstring
        assignment, it writes past the buffer and clobbers the next variable
        (bug-pascal-shortstring-no-truncation-buffer-overrun). Until that lands,
        every value here is clamped with Copy(..., 1, N) so the generator stays on
        defined ground. Drop the clamp when the ticket resolves -- truncation is
        worth testing, and this is the line that turns it back on.
        """
        cap = 8
        inner = self.str_expr(scope, depth)
        if NO_SHORTSTRING_TRUNCATION:
            return "Copy(%s, 1, %d)" % (inner, cap)
        return inner

    def str_lit(self):
        """A string literal, never exactly one character long.

        A one-character literal is typed CHAR, and pxx will not promote it to a
        string where FPC does (compat-pascal-copy-of-char-literal) -- so a
        generated `Copy('a', i, n)` is rejected outright. Filed; skipped here until
        it lands, because re-finding a ticketed bug every slice is noise.
        """
        n = self.rnd.randint(0, 5)
        if NO_ONE_CHAR_STRING_LITERAL and n == 1:
            n = 2
        return "'%s'" % "".join(self.rnd.choice("abcdefgh") for _ in range(n))

    def int_paths(self):
        """Integer LVALUES reachable through records, arrays and pointers.

        The trick that makes the whole widening cheap: a path like `r0.r0n.r0i1`,
        `r0.r0a[2]` or `pr0^.r0f0` behaves exactly like a plain integer variable --
        it can be read in any expression and assigned to. So they are handed to the
        existing expression machinery AS variables, and every operator, cast,
        comparison and function argument the generator already knows how to build
        immediately works through a deref, a field selector and an index. No new
        expression code at all.

        Field OFFSETS are what this actually tests: a deref that resolves fields at
        offset 0, a nested record whose alignment differs packed vs unpacked, an
        indexed element whose stride is wrong.
        """
        out = []
        for r in self.recs:
            g = "r%dg" % r["idx"]
            for fn, ft in r["fields"]:
                out.append(("%s.%s" % (g, fn), ft))
            for fn, ft in r["inner"]:
                out.append(("%s.r%dn.%s" % (g, r["idx"], fn), ft))
            an, n, at = r["arr"]
            for k in range(n):
                out.append(("%s.%s[%d]" % (g, an, k), at))
            # THROUGH THE POINTER. pr<i> is set to @r<i>g at init and never
            # reassigned to nil, so every deref below is live by construction.
            p = "pv%d" % r["idx"]
            for fn, ft in r["fields"]:
                out.append(("%s^.%s" % (p, fn), ft))
            for fn, ft in r["inner"]:
                out.append(("%s^.r%dn.%s" % (p, r["idx"], fn), ft))
        for a in self.arrs:
            for k in range(a["n"]):
                out.append(("%s[%d]" % (a["name"], k), a["ty"]))
        return out

    def enum_reads(self):
        """ord(enum) reads -- readable in any integer expression, NOT assignable.

        stmt() takes `scope` (what may be read) and `assignable` (what may be
        written) separately, so a read-only leaf costs nothing to add.

        The longint() wrapper is not decoration: BARE `ord(x)` in an integer
        expression is where pxx applies a boolean `not` instead of a bitwise one
        (bug-pascal-not-of-ord-uses-boolean-negation -- which this very leaf found,
        the first time the enum rung ran). The cast is the workaround; remove it
        when that ticket lands, because the bare shape is the one worth fuzzing.
        """
        cast = "longint(ord(%s))" if NO_BARE_NOT_ORD else "ord(%s)"
        return [(cast % e["var"], INT_TYPES[4]) for e in self.enumvars]

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
            return self.str_lit()
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

    def gen_modeprocs(self):
        """Procedures with var / const / out parameters.

        PROCEDURES, and called only as STATEMENTS -- never functions inside an
        expression. A var/out parameter writes through to the caller's variable, so
        a call sitting inside an expression could mutate a variable the same
        expression also reads, and Pascal does not fix the evaluation order of
        operands. The program's answer would then depend on a choice the language
        leaves open, and the two compilers would "disagree" with nobody at fault --
        the false-signal class that cost 3% of the corpus once already
        (bug-t-pasmith-order-dependent-programs). Statement order IS specified, so
        this stays on defined ground.

        `out` is never READ in the body: an out parameter arrives uninitialised by
        definition, and reading it would be exactly the uninitialised-read UB the
        generator promises never to emit.
        """
        rnd = self.rnd
        L = []
        for i in range(self.nmodeprocs):
            params = []
            for j in range(rnd.randint(2, 3)):
                params.append(("q%d" % j, rnd.choice(INT_TYPES),
                               rnd.choice(["var", "const", "out"])))
            if not any(m in ("var", "out") for _, _, m in params):
                n, t, _ = params[0]
                params[0] = (n, t, "var")
            name = "MP%d" % i
            self.modeprocs.append({"name": name, "params": params})
            sig = "; ".join("%s %s: %s" % (m, n, t.name) for n, t, m in params)
            L.append("procedure %s(%s);" % (name, sig))
            L.append("begin")
            consts = [(n, t) for n, t, m in params if m == "const"]
            for n, t, m in params:
                if m == "var":
                    src = consts[0][0] if consts else "1"
                    L.append("  %s := %s(%s + %s(%s));" % (n, t.name, n, t.name, src))
                    L.append("  Mix(int64(%s));" % n)
                elif m == "out":
                    src = consts[0][0] if consts else lit_for(t, rnd)
                    L.append("  %s := %s(%s);" % (n, t.name, src))
                    L.append("  Mix(int64(%s));" % n)
            L.append("end;")
            L.append("")
        return L

    def init_wide(self):
        """Initialise every widened global. EVERY field, element and node.

        Not thoroughness for its own sake: an uninitialised read is undefined, and
        the checksum folds all live state at exit -- so a single field left unset
        would make the program's output depend on whatever was in memory, and the
        two compilers would differ for a reason that is nobody's bug. This is the
        UB-free-by-construction invariant, applied to the new state.
        """
        rnd = self.rnd
        L = []
        for r in self.recs:
            i = r["idx"]
            for fn, ft in r["fields"]:
                L.append("  r%dg.%s := %s;" % (i, fn, lit_for(ft, rnd)))
            for fn, ft in r["inner"]:
                L.append("  r%dg.r%dn.%s := %s;" % (i, i, fn, lit_for(ft, rnd)))
            an, n, at = r["arr"]
            for k in range(n):
                L.append("  r%dg.%s[%d] := %s;" % (i, an, k, lit_for(at, rnd)))
            if r["short"]:
                L.append("  r%dg.%s := %s;" % (i, r["short"][0], self.str_lit()))
            L.append("  r%dg.next := nil;" % i)
            # The copy target must be live too -- the exit fold reads it.
            L.append("  r%dg2 := r%dg;" % (i, i))
            L.append("  pv%d := @r%dg;" % (i, i))
            # A heap chain of exactly CHAIN nodes, head h<i>, last next = nil. Built
            # with New/Dispose so the forward pointer type is exercised against real
            # heap objects, not just @-of-a-global.
            L.append("  h%d := nil;" % i)
            L.append("  for li0 := 0 to %d do" % (CHAIN - 1))
            L.append("  begin")
            L.append("    New(w%d);" % i)
            for fn, ft in r["fields"]:
                L.append("    w%d^.%s := %s(li0 + %s);" % (i, fn, ft.name,
                                                           lit_for(ft, rnd)))
            for fn, ft in r["inner"]:
                L.append("    w%d^.r%dn.%s := %s;" % (i, i, fn, lit_for(ft, rnd)))
            for k in range(n):
                L.append("    w%d^.%s[%d] := %s;" % (i, an, k, lit_for(at, rnd)))
            if r["short"]:
                L.append("    w%d^.%s := %s;" % (i, r["short"][0], self.str_lit()))
            L.append("    w%d^.next := h%d;" % (i, i))
            L.append("    h%d := w%d;" % (i, i))
            L.append("  end;")
        for a in self.arrs:
            for k in range(a["n"]):
                L.append("  %s[%d] := %s;" % (a["name"], k, lit_for(a["ty"], rnd)))
        for e in self.enumvars:
            L.append("  %s := %s;" % (e["var"], rnd.choice(e["ty"]["vals"])))
        for s in self.setvars:
            vals = [v for v in s["enum"]["vals"] if rnd.random() < 0.5]
            L.append("  %s := [%s];" % (s["var"], ", ".join(vals)))
        for sh in self.shorts:
            L.append("  %s := %s;" % (sh, self.str_lit()))
        return L

    # -- folding live state into the checksum --------------------------------
    # Used by BOTH the exit fold and --trace's Snap. They must agree: state that
    # only the exit fold sees is state a trace checkpoint cannot localise, and the
    # divergence then shows up as "the last statement", wherever it really was.

    def scalar_folds(self):
        """Every integer-ish live value: globals, record fields (incl. through the
        nested record and the inline array), standalone arrays, enum ordinals."""
        out = []
        for n, t in self.globals:
            out.append("ord(%s)" % n if t.kind in ("bool", "char") else "int64(%s)" % n)
        for path, _t in self.int_paths():
            if "^" in path:
                continue      # pr<i>^ aliases r<i>g: folding both would double-count
            out.append("int64(%s)" % path)
        for r in self.recs:
            # The copy target too -- a record assignment that copies the wrong number
            # of bytes shows up here and nowhere else.
            i = r["idx"]
            out.append("int64(r%dg2.%s)" % (i, r["fields"][0][0]))
        for e in self.enumvars:
            out.append("ord(%s)" % e["var"])
        return out

    def str_folds(self):
        return [n for n, _ in self.strs] + list(self.shorts)

    def set_folds(self):
        return [(s["var"], s["iter"]) for s in self.setvars]

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
                 "--classes %d --objs %d --strs %d --recs %d --arrs %d --enums %d "
                 "--shorts %d --excepts %d --modeprocs %d }"
                 % (self.nvars, self.nfuncs, self.nstmts, self.maxdepth,
                    self.nclasses, self.nobjs, self.nstrs, self.nrecs, self.narrs,
                    self.nenums, self.nshorts, self.nexcepts, self.nmodeprocs))
        L.append("{$mode objfpc}")
        if self.nexcepts:
            # Exception lives in sysutils in BOTH compilers -- verified: each
            # rejects `raise Exception.Create` without it, with the same complaint.
            L.append("uses sysutils;")
        # Wraparound is the DEFINED behaviour we test; range/overflow checks
        # off means arithmetic is total, so there is no trap to diverge on.
        L.append("{$Q-}")
        L.append("{$R-}")
        L.append("")
        L += self.gen_types()
        clsdecl = self.gen_classes() if self.nclasses else []
        L += clsdecl
        L.append("var")
        L.append("  cs: qword;")
        for n, t in self.globals:
            L.append("  %s: %s;" % (n, t.name))
        for i in range(self.nstrs):
            self.strs.append(("s%d" % i, STR))
            L.append("  s%d: ansistring;" % i)
        for r in self.recs:
            i = r["idx"]
            #   r<i>g   the record itself         r<i>g2  a copy target
            #   pr<i>   a pointer AT r<i>g        h<i>    the head of a heap chain
            #   w<i>    a walker over that chain
            L.append("  r%dg, r%dg2: TR%d;" % (i, i, i))
            L.append("  pv%d, h%d, w%d: PR%d;" % (i, i, i, i))
        for i in range(self.narrs):
            self.arrs.append({"name": "ar%d" % i, "n": 4, "ty": INT_TYPES[4]})
            L.append("  ar%d: array[0..3] of longint;" % i)
        if self.arrs:
            L.append("  %s: longint;" % self.arriter)
        for i, e in enumerate(self.enums):
            self.enumvars.append({"var": "ev%d" % i, "ty": e})
            L.append("  ev%d: %s;" % (i, e["name"]))
        for i, s in enumerate(self.sets):
            self.setvars.append({"var": "sv%d" % i, "enum": s["enum"],
                                 "iter": "si%d" % i})
            L.append("  sv%d: %s;" % (i, s["name"]))
            L.append("  si%d: %s;" % (i, s["enum"]["name"]))   # for..in control var
        for i in range(self.nshorts):
            self.shorts.append("sh%d" % i)
            L.append("  sh%d: string[8];" % i)
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
            decl = "var s: qword; i: longint;"
            for sv, it in self.set_folds():
                decl += " %s: %s;" % (it + "s", self.setvars[
                    [x["var"] for x in self.setvars].index(sv)]["enum"]["name"])
            L.append(decl)
            L.append("begin")
            L.append("  s := cs;")
            for e in self.scalar_folds():
                L.append("  s := qword(s * 1000003) xor qword(%s);" % e)
            for n in self.str_folds():
                # String state must be in the trace too, or a divergence in a
                # string statement would show a clean checkpoint and mislocate.
                L.append("  for i := 1 to Length(%s) do "
                         "s := qword(s * 31) xor qword(ord(%s[i]));" % (n, n))
            for sv, it in self.set_folds():
                L.append("  for %ss in %s do s := qword(s * 31) xor qword(ord(%ss));"
                         % (it, sv, it))
            L.append("  writeln(s);")
            L.append("end;")
            L.append("")
        L += safe_helpers()
        L.append("")
        L += self.gen_modeprocs()
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
            L.append("  %s := %s;" % (n, self.str_lit()))
        L += self.init_wide()
        for i in range(self.nclasses and self.nobjs):
            # Instantiate a RANDOM class from the chain into a base-typed slot.
            L.append("  o%d := TC%d.Create(%d);"
                     % (i, rnd.randrange(self.nclasses), rnd.randint(1, 50)))
        L.append("")
        # Record fields, array elements and pointer derefs enter the scope AS
        # VARIABLES (see int_paths), so every operator the generator already knows
        # works through a field selector, an index and a `^` with no new code.
        paths = self.int_paths()
        body_scope = (list(self.globals) + list(self.strs) + paths
                      + self.enum_reads())
        assignable = list(self.globals) + paths
        for _ in range(self.nstmts):
            L += self.stmt(body_scope, self.maxdepth, 1, assignable)
            if self.trace:
                self.ckpt += 1
                # kind= is machine-read by pasmith_run's signature(): it names the
                # construct a divergence sits on, which is how 500 reports of one
                # bug collapse into one ledger entry instead of 500 tickets.
                L.append("  Snap;   { checkpoint %d kind=%s }" % (self.ckpt, self.kind))
        L.append("")
        L.append("  { fold ALL live state into one number: the sole output }")
        for e in self.scalar_folds():
            L.append("  Mix(%s);" % e)
        for n in self.str_folds():
            L.append("  MixStr(%s);" % n)
        for sv, it in self.set_folds():
            L.append("  for %s in %s do Mix(ord(%s));" % (it, sv, it))
        for r in self.recs:
            # Free the heap chain: exactly one Dispose per New, in one place, and
            # nothing touches a node afterwards. Same lifetime discipline the class
            # rung uses for Free -- an over- or under-freed node is a bug we want to
            # catch, not one we want to WRITE.
            i = r["idx"]
            L.append("  w%d := h%d;" % (i, i))
            L.append("  for li0 := 0 to %d do begin" % (CHAIN - 1))
            L.append("    pv%d := w%d^.next; Dispose(w%d); w%d := pv%d;"
                     % (i, i, i, i, i))
            L.append("  end;")
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
    ap.add_argument("--classes", type=int, default=None,
                    help="length of the inheritance chain (0 = no OOP). Every class "
                         "overrides its parent's virtuals and calls inherited, so one "
                         "call through a base-typed ref walks the whole chain.")
    ap.add_argument("--objs", type=int, default=3, help="base-typed object slots")
    ap.add_argument("--strs", type=int, default=None, help="ansistring globals")
    # The widened rungs. Each is a bug class we have SHIPPED and the scalar grammar
    # could not express -- see feature-pasmith-widen-grammar.
    ap.add_argument("--recs", type=int, default=None,
                    help="record types: nested + packed + inline array + inline "
                         "string[N] + a FORWARD pointer type (PRk = ^TRk declared "
                         "before TRk -- the b338 shape), a heap chain built with "
                         "New/Dispose, whole-record copies and `with`.")
    ap.add_argument("--arrs", type=int, default=None,
                    help="static array globals (indexed reads/writes + for..in)")
    ap.add_argument("--enums", type=int, default=None,
                    help="enum types, one set type each: enum identity (b342), "
                         "case-of-enum, set ops, `in`, for..in over a set")
    ap.add_argument("--shorts", type=int, default=None, help="string[8] globals")
    ap.add_argument("--excepts", type=int, default=None,
                    help="length of the exception class chain (EPas0 < EPas1 < ...). "
                         "Raises a DERIVED class and catches it on a BASE one -- the "
                         "b339 shape. Every raise is caught by construction.")
    ap.add_argument("--modeprocs", type=int, default=None,
                    help="procedures with var/const/out params, called as statements")
    ap.add_argument("--wide", action="store_true",
                    help="shorthand: turn on every widened rung at a sensible size")
    ap.add_argument("--wide-p", type=float, default=0.45,
                    help="probability a statement is one of the widened kinds")
    a = ap.parse_args()
    if a.wide:
        # `x or default` would be WRONG here: it cannot distinguish "not given" from
        # "given as 0", so `--wide --shorts 0` would silently turn shortstrings back
        # ON. Turning a single rung OFF is exactly what you need when one rung is
        # blocked (e.g. the cross targets reject records holding a string[N]), so
        # the defaults only fill in flags the user did not pass at all.
        for f, v in (("recs", 2), ("arrs", 2), ("enums", 2), ("shorts", 2),
                     ("excepts", 3), ("modeprocs", 2), ("strs", 3), ("classes", 3)):
            if getattr(a, f) is None:
                setattr(a, f, v)
    for f in ("recs", "arrs", "enums", "shorts", "excepts", "modeprocs",
              "strs", "classes"):
        if getattr(a, f) is None:
            setattr(a, f, 0 if f != "classes" else 0)
    src = Gen(a.seed, a.vars, a.funcs, a.stmts, a.depth, a.trace,
              a.classes, a.objs, a.strs, a.recs, a.arrs, a.enums, a.shorts,
              a.excepts, a.modeprocs, a.wide_p).gen()
    if a.output:
        with open(a.output, "w") as f:
            f.write(src)
    else:
        sys.stdout.write(src)
    return 0


if __name__ == "__main__":
    sys.exit(main())
