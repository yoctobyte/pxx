#!/usr/bin/env python3
"""The conditional probe's save/restore list must cover the directive baseline's.

WHY THIS EXISTS. `{$if declared(X)}` is answered by lexing a used unit into a
scratch region (PasCondNameDeclaredInUses). Lexing a unit RUNS ITS DIRECTIVES,
so the probe saves the caller's lexer state and puts it back. If a directive is
added to PasSnapshotDirectiveBaseline and not to PasProbeSaveLexState, that
directive escapes the probe into the rest of the main file's lex --

  AND THE FAILURE IS NOT AN ERROR. It is a different program: a leaked
  {$PACKRECORDS} changes a record's ABI, a leaked {$define} flips an {$ifdef} to
  the other arm. Measured 2026-09-09 with the probe wired and the save/restore
  pair absent: a {$DEFINE} in a used unit made the MAIN program's {$ifdef} take
  the true arm where fpc takes the false one -- which is
  bug-p-a-units-define-leaks-into-the-units-it-uses being reintroduced by a
  second copy of a list.

So the two enumerations are checked against each other rather than trusted to
stay in step. Three assertions:

  1. every global PasSnapshotDirectiveBaseline snapshots is saved by
     PasProbeSaveLexState;
  2. PasProbeRestoreLexState restores exactly the set PasProbeSaveLexState
     saved, neither more nor less (an asymmetric pair silently keeps one of the
     probed unit's values);
  3. every PasDefine* array PasSnapshotDefineBaseline copies is copied by the
     probe pair too.

Exit 1 and name the missing entries. Positive control: delete any one line from
PasProbeSaveLexState and this must fail (asserted in the test wiring).
"""
import re
import sys
import pathlib

SRC = pathlib.Path(__file__).resolve().parent.parent / "compiler" / "paslexer.inc"


def body(text, name):
    """The statements of procedure `name`, up to its terminating `end;`."""
    m = re.search(r"^procedure %s;\n(.*?)^end;$" % re.escape(name), text,
                  re.S | re.M)
    if not m:
        sys.exit("probe_state_lists: cannot find procedure %s in %s" % (name, SRC))
    return m.group(1)


LITERALS = {"True", "False", "Nil", "nil"}


def rhs_globals(src, lhs_prefix):
    """Globals appearing on the RHS of `<lhs_prefix>Foo := Global;`.

    `DirBaseValid := True` is a flag about the snapshot, not a directive being
    snapshotted, so literals are not globals to carry."""
    found = set(re.findall(r"^\s*%s\w+\s*:=\s*(\w+);" % re.escape(lhs_prefix),
                           src, re.M))
    return found - LITERALS


def lhs_globals(src, rhs_prefix):
    """Globals assigned FROM `<rhs_prefix>Foo`, i.e. `Global := ProbeSaveFoo;`."""
    return set(re.findall(r"^\s*(\w+)\s*:=\s*%s\w+;" % re.escape(rhs_prefix),
                          src, re.M))


def arrays(src):
    """The SOURCE PasDefine* arrays copied element-wise, i.e. the RHS.

    Both sides of a copy match the same shape -- ``PasDefineBaseActive[i] :=
    PasDefineActive[i]`` -- and it is the right-hand one that names the live
    table each copy has to cover."""
    return set(re.findall(r":=\s*(PasDefine\w+)\[i\];", src))


def main():
    text = SRC.read_text()
    dir_base = rhs_globals(body(text, "PasSnapshotDirectiveBaseline"), "DirBase")
    probe_save = rhs_globals(body(text, "PasProbeSaveLexState"), "ProbeSave")
    probe_rest = lhs_globals(body(text, "PasProbeRestoreLexState"), "ProbeSave")

    fail = []

    missing = sorted(dir_base - probe_save)
    if missing:
        fail.append(
            "PasProbeSaveLexState does not save %d directive global(s) that\n"
            "PasSnapshotDirectiveBaseline snapshots: %s\n"
            "  Each one LEAKS from a probed unit into the rest of the main file's\n"
            "  lex, and leaks silently -- it changes the program, not the exit code."
            % (len(missing), ", ".join(missing)))

    only_saved = sorted(probe_save - probe_rest)
    only_restored = sorted(probe_rest - probe_save)
    if only_saved:
        fail.append("saved but never restored (the probed unit's value survives): %s"
                    % ", ".join(only_saved))
    if only_restored:
        fail.append("restored but never saved (restores an undefined slot): %s"
                    % ", ".join(only_restored))

    def_base = arrays(body(text, "PasSnapshotDefineBaseline"))
    probe_arr = arrays(body(text, "PasProbeSaveLexState"))
    missing_arr = sorted(def_base - probe_arr)
    if missing_arr:
        fail.append("PasProbeSaveLexState does not save define array(s): %s"
                    % ", ".join(missing_arr))

    if fail:
        print("probe_state_lists: FAIL")
        for f in fail:
            print("  " + f)
        return 1

    print("probe_state_lists: OK (%d directive globals, %d define arrays, "
          "save/restore symmetric)" % (len(dir_base), len(def_base)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
