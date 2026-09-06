#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: what counts as EVIDENCE that something runs a test file.

`check_test_wiring.py` answers one question -- does any rule run this file --
and it answers it textually, which is right (a reference is a reference
whichever variable expands around it) and was too broad in two ways:

1. **A comment counted as wiring.** A commented-out or merely descriptive
   mention marked an orphan WIRED, so the checker reported nothing. That is
   the bad failure direction: the gap it exists to surface stays invisible,
   and there is no output to notice.

2. **A tools/ mention counted as PROOF, and drove a STALE verdict.** The
   stale-exemption report says "this entry now only hides future gaps", which
   invites a deletion -- and deleting a correct exemption re-opens the gap it
   was covering. It fired on `test/csqlite_file_probe.c`, whose only live
   reference in the tree is a data tuple in
   `tools/testmgr_hardcoded_tmp_devtest.py` that asserts about the file's
   CONTENT and never builds it. The exemption was correct.

The second is deliberately NOT fixed by guessing whether a script "looks like
a runner" -- a devtest listing test files as data mentions them exactly like a
runner that executes them, and a heuristic there goes stale silently. The fix
is to grade the evidence and hand the reader the citation.

Guards run over a throwaway git tree, so every branch is PROVEN to fire
rather than inferred from live data that happens to have no instance.

Run: tools/check_test_wiring_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def _mod(root):
    """Load the checker rebound to a scratch tree."""
    spec = importlib.util.spec_from_file_location(
        "ctw", os.path.join(HERE, "check_test_wiring.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.ROOT = root
    m.EXEMPT = os.path.join(root, "test", "UNWIRED.txt")
    return m


def _tree(makefile="", tools=None, tests=None, unwired=""):
    """A minimal repo: a Makefile, some tools/ scripts, some test/ subjects."""
    root = tempfile.mkdtemp()
    os.makedirs(os.path.join(root, "test"))
    os.makedirs(os.path.join(root, "tools"))
    open(os.path.join(root, "Makefile"), "w").write(makefile)
    for name, body in (tools or {}).items():
        open(os.path.join(root, "tools", name), "w").write(body)
    for name in (tests or []):
        full = os.path.join(root, "test", name)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "w").write("x\n")
    open(os.path.join(root, "test", "UNWIRED.txt"), "w").write(unwired)
    for cmd in (["git", "init", "-q"],
                ["git", "add", "-A"]):
        subprocess.run(cmd, cwd=root, capture_output=True)
    return root


def _run(root):
    """(exit code, stdout) of one check over that tree."""
    m = _mod(root)
    import io
    from contextlib import redirect_stdout
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = m.main()
    return rc, buf.getvalue()


# ------------------------------------------------ 1. a comment is not wiring --

def t_a_commented_mention_does_not_wire_a_file():
    """The original defect, in its smallest form."""
    root = _tree(makefile="# same shape as test/orphan.pas\nall:\n\techo hi\n",
                 tests=["orphan.pas"])
    rc, out = _run(root)
    assert "test/orphan.pas" in out, \
        "a mention inside a Makefile COMMENT was accepted as a build rule: %s" % out
    assert rc == 1
    return "a Makefile comment does not count as wiring"


def t_a_hash_comment_inside_a_recipe_body_does_not_wire():
    """A recipe line is indented; the comment marker still leads the line."""
    root = _tree(makefile="all:\n\t# test/orphan.pas is the same shape\n\techo hi\n",
                 tests=["orphan.pas"])
    _, out = _run(root)
    assert "test/orphan.pas" in out, out
    return "a `#` line inside a recipe body does not count as wiring"


def t_a_real_rule_still_wires():
    """The fix must not swing the other way and report wired files."""
    root = _tree(makefile="all:\n\t./run test/orphan.pas\n", tests=["orphan.pas"])
    rc, out = _run(root)
    assert "test/orphan.pas" not in out, \
        "a live recipe line stopped counting as wiring: %s" % out
    assert rc == 0, out
    return "a live recipe line still wires its file"


def t_a_trailing_comment_is_still_counted_and_that_is_deliberate():
    """The stated aperture, guarded so it cannot change silently.

    `#` is legal inside a recipe's shell quoting, so cutting a line at the
    first one would drop REAL references -- the worse direction. A guard on
    documented-but-imperfect behaviour is what stops it drifting into
    accidental behaviour.
    """
    root = _tree(makefile="all:\n\techo hi   # test/orphan.pas\n",
                 tests=["orphan.pas"])
    _, out = _run(root)
    assert "test/orphan.pas" not in out, \
        "trailing comments are now stripped -- intended, but update the " \
        "documented aperture in wired_paths() and this guard together"
    return "a TRAILING comment still counts (documented aperture)"


# --------------------------------------- 2. how strong is the stale evidence --

def t_a_makefile_wired_exemption_is_hard_stale():
    root = _tree(makefile="all:\n\t./run test/ex.pas\n", tests=["ex.pas"],
                 unwired="test/ex.pas  no longer true\n")
    rc, out = _run(root)
    assert "STALE" in out and "test/ex.pas" in out, out
    assert rc == 1
    return "an exemption the Makefile really wires is hard STALE"


def t_a_missing_file_is_hard_stale():
    root = _tree(unwired="test/gone.pas  file was deleted\n")
    rc, out = _run(root)
    assert "STALE" in out and "test/gone.pas" in out, out
    assert rc == 1
    return "an exemption for a file that no longer exists is hard STALE"


def t_a_tools_only_mention_is_ADVISORY_not_stale():
    """The measured false positive: a devtest naming a file as DATA."""
    root = _tree(tools={"x_devtest.py": 'CASES = [("test/ex.c", "/tmp/p.db")]\n'},
                 tests=["ex.c"], unwired="test/ex.c  needs a gitignored corpus\n")
    rc, out = _run(root)
    assert "STALE" not in out, \
        "a bare mention in a tools/ script was reported as STALE, which " \
        "invites deleting a correct exemption: %s" % out
    assert "verify before deleting" in out, out
    return "a tools/-only mention is advisory, not STALE"


def t_the_advisory_cites_its_evidence():
    """A verdict a reader cannot check is a verdict they must take on faith."""
    root = _tree(tools={"x_devtest.py": 'CASES = [("test/ex.c", "/tmp/p.db")]\n'},
                 tests=["ex.c"], unwired="test/ex.c  needs a gitignored corpus\n")
    _, out = _run(root)
    assert "tools/x_devtest.py:1" in out, \
        "the advisory does not say WHERE the reference was found: %s" % out
    return "the advisory cites file:line"


def t_an_advisory_alone_does_not_fail_the_check():
    """Severity has to reach the exit code, or it is only a wording change."""
    root = _tree(tools={"x_devtest.py": 'CASES = [("test/ex.c", "/tmp/p.db")]\n'},
                 tests=["ex.c"], unwired="test/ex.c  needs a gitignored corpus\n")
    rc, _ = _run(root)
    assert rc == 0, "an advisory-only run failed the check (exit %d)" % rc
    return "an advisory alone does not fail the check"


def t_a_real_unwired_file_still_fails():
    """The check's whole purpose, guarded against every narrowing above."""
    root = _tree(makefile="all:\n\techo hi\n", tests=["orphan.pas"])
    rc, out = _run(root)
    assert rc == 1 and "nothing runs them" in out, out
    return "an genuinely unwired subject still fails the check"


def t_a_reasonless_exemption_is_still_refused():
    root = _tree(tests=["ex.pas"], unwired="test/ex.pas\n")
    rc, out = _run(root)
    assert rc == 1 and "no REASON" in out, out
    return "an exemption with no reason is still refused"


# ---------------------------------- 5. a DIRECTORY reference vs a truncation --
#
# `-Futest/case_units` names a directory and never the unit inside it, so
# crediting the whole directory is right. The rule that implemented it -- a
# token with a `/` and no extension -- was satisfied just as well by a path the
# collector could not finish reading, because its pattern excludes `$`:
#
#     local src="$ROOT/test/gui/$name.pas"      ->  token `test/gui/`
#
# which blanketed all 26 files under test/gui while gui_suite.sh ran eleven of
# them. Five were run by nothing and the report said zero. These guards pin
# each arm, because the arms are one character apart and the wrong one fails
# SILENTLY -- it can only remove entries from the report, never add one.


def t_a_variable_truncated_path_does_not_blanket_its_directory():
    """The defect, in its smallest form."""
    root = _tree(tools={"suite.sh": 'src="$ROOT/test/gui/$name.pas"\n'},
                 tests=["gui/ran.pas", "gui/orphan.pas"])
    rc, out = _run(root)
    assert "test/gui/orphan.pas" in out, \
        "a path truncated at a shell variable blanketed its whole directory " \
        "-- the false all-clear this classifier exists to stop: %s" % out
    assert rc == 1
    return "a path truncated at a variable does not blanket its directory"


def t_a_bare_stem_in_the_same_script_credits_that_file_only():
    """The other half: the script DOES supply $name, as a bare word."""
    root = _tree(tools={"suite.sh": 'src="$ROOT/test/gui/$name.pas"\n'
                                    'run_gui_test ran\n'},
                 tests=["gui/ran.pas", "gui/orphan.pas"])
    _, out = _run(root)
    assert "test/gui/ran.pas" not in out, \
        "a file whose stem the same script names as a bare word was reported " \
        "unwired -- a false RED, which trains people to skip the check: %s" % out
    assert "test/gui/orphan.pas" in out, out
    return "a bare stem in the same script credits that file, and only it"


def t_a_same_stem_path_component_elsewhere_does_not_credit():
    """Measured, not hypothetical: gui_suite.sh names apps/ide/eliah/main.pas,
    which credited the helloworld/main.pas sitting under the gui test dir -- a
    different file that merely shares a stem. A path component naming something
    else is not evidence.

    NOTE the spelling above. Writing that file's real path here CLEARED IT: the
    checker counts docstring prose as a reference (deliberately -- see
    wired_paths()'s stated aperture, which strips full-line comments only), so
    the sentence explaining the orphan became the evidence that it runs. The
    report went 6 -> 5 on the strength of this write-up. Same self-witness
    family as the SKIP_DIRS literal one guard below, one level up, and the
    reason this file must not spell a live test path in prose."""
    root = _tree(tools={"suite.sh": 'src="$ROOT/test/gui/$name.pas"\n'
                                    'other="$ROOT/apps/eliah/main.pas"\n'},
                 tests=["gui/main.pas"])
    _, out = _run(root)
    assert "test/gui/main.pas" in out, \
        "a same-stem PATH COMPONENT for an unrelated file was accepted as " \
        "evidence that this one runs: %s" % out
    return "a same-stem path component elsewhere is not evidence"


def t_a_glob_over_a_directory_still_blankets_it():
    """The one truncation that IS a directory reference: it runs them all."""
    root = _tree(makefile="all:\n\tfor p in test/corpus/*.pas; do ./run $$p; done\n",
                 tests=["corpus/a.pas", "corpus/b.pas"])
    rc, out = _run(root)
    assert "test/corpus" not in out, \
        "a glob over a directory stopped counting as running its contents: %s" % out
    assert rc == 0, out
    return "a glob over a directory still blankets it"


def t_a_search_path_flag_still_blankets_its_directory():
    """The case the rule was written for must not regress."""
    root = _tree(makefile="all:\n\t./pxx -Futest/units test/main.pas\n",
                 tests=["units/helper.pas", "main.pas"])
    rc, out = _run(root)
    assert "test/units/helper.pas" not in out, \
        "-Fu<dir> stopped crediting the units inside it: %s" % out
    assert rc == 0, out
    return "a -Fu<dir> search path still blankets its directory"


def t_the_checker_does_not_scan_its_own_source():
    """A tool must not be its own witness.

    The checker lives in tools/ and scans tools/, so its own SKIP_DIRS literal
    was collected as a reference to the directories it names. Nothing was lost
    at the time -- those directories are skipped anyway -- but a literal path
    written into this file would silently exempt whatever it named, with no
    rule behind it.
    """
    root = _tree(tools={"check_test_wiring.py": 'SKIP = ("test/orphan.pas",)\n'},
                 tests=["orphan.pas"])
    _, out = _run(root)
    assert "test/orphan.pas" in out, \
        "the checker credited a path named in its own source: %s" % out
    return "the checker does not read its own source as evidence"


def t_stem_evidence_reaches_direct_children_only():
    """A truncated token names a child of that directory, never a grandchild.

    `$ROOT/testdir/$name.pas` ends at the variable with `.pas` after it, so the
    file it names sits directly in that directory. Letting the stem search
    descend cost a real orphan: this very file carries such a token inside a
    fixture string AND defines its own `def main()`, and that `main` credited
    the helloworld/main.pas two levels down. The report went 6 -> 5 because a
    devtest mentioned a directory and happened to have a main().
    """
    root = _tree(tools={"suite.sh": 'src="$ROOT/test/gui/$name.pas"\n'
                                    'run_gui_test direct\n'
                                    'def deep\n'},
                 tests=["gui/direct.pas", "gui/sub/deep.pas"])
    _, out = _run(root)
    assert "test/gui/direct.pas" not in out, out
    assert "test/gui/sub/deep.pas" in out, \
        "a bare stem credited a file two levels down, which a `$name.pas` " \
        "token cannot reach: %s" % out
    return "stem evidence reaches direct children only"


# ------------------------------------------- --since: the PER-PUSH question --
#
# The census answers "what is unwired in this tree?" and is expensive to act on,
# so it runs in limited+full. `--since` answers "did THIS push add a test that
# nothing runs?", which is cheap and lands on the agent who can still fix it in
# seconds. frankwasm wrote nine tests on 2026-08-30; the census named all nine
# and exited 1 all day, and one was a campaign's acceptance test run by nothing
# but its author's hand.

def _committed_tree(makefile, base_tests, new_tests, unwired="",
                    new_blobs=None, uncommitted_blobs=None):
    """A tree with a base COMMIT, then a second commit adding `new_tests`.
    -> (root, base_sha). Scoped mode needs real history, not just an index.

    `new_blobs` ({name: bytes}) go in that second COMMIT; `uncommitted_blobs`
    are left untracked. The split matters and is not decoration: of the three
    real probe binaries that reached origin, two were COMMITTED, so a guard
    exercised only against an untracked file would have passed on them.
    """
    root = _tree(makefile=makefile, tests=base_tests, unwired=unwired)
    env = ["-c", "user.email=t@pxx", "-c", "user.name=devtest"]
    subprocess.run(["git"] + env + ["commit", "-q", "-m", "base"],
                   cwd=root, capture_output=True)
    base = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root,
                          capture_output=True, text=True).stdout.strip()
    for name in new_tests:
        full = os.path.join(root, "test", name)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "w").write("x\n")
    for name, blob in (new_blobs or {}).items():
        open(os.path.join(root, "test", name), "wb").write(blob)
    subprocess.run(["git", "add", "-A"], cwd=root, capture_output=True)
    subprocess.run(["git"] + env + ["commit", "-q", "-m", "add tests"],
                   cwd=root, capture_output=True)
    for name, blob in (uncommitted_blobs or {}).items():
        open(os.path.join(root, "test", name), "wb").write(blob)
    return root, base


# A minimal ELF header. Only the first four bytes are read, but a truncated
# stub would make the guard look stricter than it is -- this is the magic plus
# enough of a header that the file is what it claims to be.
ELF_STUB = b"\x7fELF\x02\x01\x01\x00" + b"\x00" * 56


def _run_since(root, rev):
    m = _mod(root)
    import io
    from contextlib import redirect_stdout
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = m.main(["--since", rev])
    return rc, buf.getvalue()


def t_since_names_a_test_THIS_push_added_and_did_not_wire():
    root, base = _committed_tree("all:\n\techo hi\n", [], ["orphan.pas"])
    rc, out = _run_since(root, base)
    assert rc == 1, "an unwired new test must fail the push gate: %s" % out
    assert "test/orphan.pas" in out, out
    assert "THIS PUSH ADDS" in out, out
    return "a test added by this push with no rule fails it"


def t_since_ignores_an_orphan_that_was_ALREADY_there():
    """The whole point of scoping: nobody inherits the backlog."""
    root, base = _committed_tree("all:\n\techo hi\n", ["old_orphan.pas"],
                                 ["new_one.pas"])
    rc, out = _run_since(root, base)
    assert "test/old_orphan.pas" not in out, \
        "a pre-existing orphan leaked into the per-push check: %s" % out
    assert "test/new_one.pas" in out, out
    return "a pre-existing orphan is the census's problem, not this push's"


def t_since_passes_when_the_new_test_IS_wired():
    root, base = _committed_tree("all:\n\t./run test/wired.pas\n", [],
                                 ["wired.pas"])
    rc, out = _run_since(root, base)
    assert rc == 0, "a properly wired new test must not fail: %s" % out
    return "wiring the test clears it"


def t_since_that_cannot_resolve_its_rev_is_NOT_a_pass():
    """The third state. A check that reports success by not running is the
    exact defect this checker exists to remove, so it exits 2, not 0."""
    root, _ = _committed_tree("all:\n\techo hi\n", [], ["orphan.pas"])
    rc, out = _run_since(root, "no-such-rev-exists")
    assert rc == 2, "cannot-scope must not be 0 or 1, got %d: %s" % (rc, out)
    assert "CANNOT SCOPE" in out and "not a pass" in out, out
    return "an unresolvable --since says so instead of passing"


def t_since_refuses_a_COMMITTED_elf_under_test():
    """The population the guard is actually about.

    Three unreferenced x86-64 executables reached origin under test/ from three
    different seats in ten days, and TWO OF THEM WERE COMMITTED. A guard
    exercised only against an untracked file would have passed on those two
    while looking like it worked, so the committed case is the control that
    counts, not the convenient one.
    """
    root, base = _committed_tree("all:\n\techo hi\n", [], [],
                                 new_blobs={"trf": ELF_STUB})
    rc, out = _run_since(root, base)
    assert rc == 1, "a committed ELF under test/ must fail the push gate: %s" % out
    assert "test/trf" in out, out
    assert "COMPILED BINARY" in out, out
    return "a committed probe binary is refused, not just an untracked one"


def t_since_refuses_an_UNTRACKED_elf_too():
    """The state the prescribed workflow is in: gate BEFORE you commit."""
    root, base = _committed_tree("all:\n\techo hi\n", [], [],
                                 uncommitted_blobs={"tgf": ELF_STUB})
    rc, out = _run_since(root, base)
    assert rc == 1, "an untracked ELF under test/ must fail too: %s" % out
    assert "test/tgf" in out, out
    return "the same refusal before the file is ever added"


def t_an_elf_named_like_nothing_is_still_caught():
    """The reason this is a magic-number read and not a name pattern.

    .gitignore carries test/test_* and test/tmp_* and both are correct; the
    names that got through match neither, BECAUSE AN AD-HOC NAME IS ARBITRARY
    BY DEFINITION. So the guard must not depend on the name at all, and this
    case uses one no pattern could have anticipated.
    """
    root, base = _committed_tree("all:\n\techo hi\n", [], [],
                                 new_blobs={"qq7": ELF_STUB})
    rc, out = _run_since(root, base)
    assert rc == 1 and "test/qq7" in out, out
    return "an arbitrary name is caught, because the check reads bytes"


def t_a_text_test_file_is_not_reported_as_a_binary():
    """The negative control, and it must fail for the RIGHT REASON.

    An unwired new .pas fails this checker anyway -- that is the pre-existing
    arm doing its job -- so `rc == 1` alone cannot show the ELF arm stayed
    quiet. The discriminator is WHICH message came out.
    """
    root, base = _committed_tree("all:\n\techo hi\n", [], ["plain.pas"])
    rc, out = _run_since(root, base)
    assert "COMPILED BINARY" not in out, \
        "a text test source was reported as a compiled binary: %s" % out
    assert "THIS PUSH ADDS" in out, out
    return "a text source trips the wiring arm, never the binary one"


def t_an_exempted_elf_is_let_through():
    """The documented escape hatch still opens.

    test/UNWIRED.txt is the one out, and a guard with no out is one people
    route around. It is deliberately not free: an entry there says "nothing
    runs this file", which is a different claim from "this executable belongs
    in the repo", and the reason has to carry that weight.
    """
    root, base = _committed_tree("all:\n\techo hi\n", [], [],
                                 unwired="test/keepme  a real binary fixture, "
                                         "checked in on purpose\n",
                                 new_blobs={"keepme": ELF_STUB})
    rc, out = _run_since(root, base)
    assert "COMPILED BINARY" not in out, \
        "an exempted binary was still refused: %s" % out
    return "an explicit UNWIRED.txt entry still opens the gate"


# --------------------------------------------------- PARKS: not-yet, owned --
# A park borrows a live ticket's authority to say "nothing runs this HERE, YET".
# The entire reason it is a separate kind from an exemption is that it EXPIRES,
# so these four guards are the mechanism, not decoration: without the expiry a
# park is just an exemption with a longer sentence, and the 37 wasm files would
# be hidden forever behind a ticket that closed months ago.


def _park_tree(reason, ticket_dir=None, ticket_slug="feature-target-wasm"):
    root = _tree(makefile="all:\n\techo hi\n",
                 tests=["wasm/a_slice.pas", "wasm/b_slice.pas", "wired.pas"],
                 unwired="test/wasm/  %s\n" % reason)
    open(os.path.join(root, "Makefile"), "w").write(
        "all:\n\t$(PXX) test/wired.pas\n")
    if ticket_dir:
        d = os.path.join(root, "devdocs", "progress", ticket_dir)
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, ticket_slug + ".md"), "w").write("# t\n")
    return root


def t_a_park_on_a_live_ticket_covers_a_whole_directory():
    rc, out = _run(_park_tree("parked:feature-target-wasm developed elsewhere",
                              "backlog"))
    assert rc == 0, out
    assert "2 file(s) PARKED" in out, out
    assert "test/wasm/" in out and "feature-target-wasm" in out, out
    # The point of the directory form: one row, not one row per leaf.
    assert "wasm/a_slice.pas" not in out, "the park listed leaves instead of the directory"
    return "a `dir/` park covers everything beneath it and reports as ONE row"


def t_a_park_is_printed_not_silently_passed():
    rc, out = _run(_park_tree("parked:feature-target-wasm developed elsewhere",
                              "backlog"))
    assert "PARKED against a live ticket" in out, out
    assert "not wired here, and that is tracked, not forgotten" in out, out
    return "a park is reported with its count and ticket, never silent"


def t_a_park_whose_ticket_CLOSED_is_refused():
    # The mechanism. If this ever passes, a park has become an exemption
    # without anyone deciding that it should.
    rc, out = _run(_park_tree("parked:feature-target-wasm shipped", "done"))
    assert rc == 1, out
    assert "PARK(S) whose ticket is no longer open" in out, out
    assert "is closed" in out, out
    return "a park expires the moment its ticket reaches done/"


def t_a_park_naming_no_ticket_at_all_is_refused():
    rc, out = _run(_park_tree("parked:no-such-ticket nothing owns this"))
    assert rc == 1, out
    assert "is missing" in out, out
    return "a park citing a ticket that does not exist is refused, not trusted"


def t_a_park_with_no_reason_is_refused_like_any_exemption():
    rc, out = _run(_park_tree("parked:feature-target-wasm", "backlog"))
    assert rc == 1, out
    assert "no REASON" in out, out
    return "a ticket slug is not a reason — the sentence is still required"


# ------------------------------------------------- 12. the runner census --
#
# A DIFFERENT QUESTION FROM EVERYTHING ABOVE, and the guards have to prove it
# separately: the subject census asks whether a build rule reaches a test, the
# runner census asks whether ANY file names the script that would run one. The
# motivating case is `test/wasm/check_nilpy_objlocal.sh`, which at fa4d9c43f^
# was named by four files and run by none of them.


def _runner_tree(files, unwired="", makefile="all:\n\techo hi\n"):
    """A tree whose test/ contents are given verbatim. -> root.

    _tree() writes every test file as "x\n", which is fine for a subject and
    useless here: the whole question is what one file's TEXT says about
    another.
    """
    root = _tree(makefile=makefile, unwired=unwired)
    for name, body in files.items():
        full = os.path.join(root, "test", name)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "w").write(body)
    subprocess.run(["git", "add", "-A"], cwd=root, capture_output=True)
    return root


def t_a_runner_named_by_nothing_is_reported():
    """The positive control. Without this the census cannot fail."""
    root = _runner_tree({"wasm/check_x.sh": "#!/bin/sh\necho hi\n"})
    rc, out = _run(root)
    assert "test/wasm/check_x.sh" in out, \
        "a runner nothing names was not reported: %s" % out
    assert "NAMED BY NOTHING" in out, out
    assert rc == 1, out
    return "a runner script nothing names is reported"


def t_a_runner_named_by_a_sibling_is_not_reported():
    """The negative control, and the reason the question is LOCAL.

    Asked globally -- reachable from the Makefile? -- the real tree answers
    47 of 48, because test/wasm/ is run by hand and its own entry point is
    named by no rule. A check that flags everything is as empty as one that
    never fires, so a sibling counts as an invoker.
    """
    root = _runner_tree({
        "wasm/check_all.sh": "#!/bin/sh\nfor c in check_x.sh; do sh $c; done\n",
        "wasm/check_x.sh": "#!/bin/sh\necho hi\n"})
    rc, out = _run(root)
    assert "check_x.sh" not in out, \
        "a runner named by its sibling entry point was reported: %s" % out
    return "a sibling entry point naming a runner counts as a reference"


def t_a_directory_park_does_NOT_cover_a_runner():
    """The correction that let this census see its own motivating case.

    A `dir/` entry answers the SUBJECT question -- nothing on master wires
    this tree and nothing should yet. Whether the directory's own entry point
    can see its own members is a different claim, and a parked tree still has
    one. Wired through _covered() first, the real test/wasm/ park -- which
    predates check_nilpy_objlocal.sh by months -- swallowed exactly the file
    this was built for, and the checker printed OK over it.
    """
    root = _runner_tree({"wasm/check_x.sh": "#!/bin/sh\necho hi\n"},
                        unwired="test/wasm/  developed on a branch\n")
    rc, out = _run(root)
    assert "test/wasm/check_x.sh" in out, \
        "a directory-level exemption hid an orphan runner: %s" % out
    assert rc == 1, out
    return "a `dir/` entry does not exempt a runner inside it"


def t_an_exact_exemption_DOES_cover_a_runner():
    """The other half: a person naming THIS runner and saying why."""
    root = _runner_tree(
        {"manual/try_it.sh": "#!/bin/sh\necho hi\n"},
        unwired="test/manual/try_it.sh  hand-run, needs a checkout we do not "
                "vendor\n")
    rc, out = _run(root)
    assert "try_it.sh" not in out, \
        "an exact exemption with a reason did not cover its runner: %s" % out
    assert rc == 0, out
    return "an exact-path exemption with a reason covers a runner"


def t_a_fixture_POINTING_BACK_at_its_runner_does_not_clear_it():
    """Measured, not hypothesised, and it is why the corpus is by extension.

    At fa4d9c43f^ the orphan was named by objlocal_slice.npy (*"N_ITERS is
    substituted by check_nilpy_objlocal.sh"*) and by wasmhost.js (*"could not
    instantiate its own fixture"*). Both are files the script USES, pointing
    back at it. A corpus of "anything that mentions the name" reads a runner's
    own dependencies as its callers, and can then never report an orphan that
    has any fixture at all -- which is every orphan worth finding.
    """
    root = _runner_tree({
        "wasm/check_x.sh": "#!/bin/sh\necho hi\n",
        "wasm/slice.npy": "# N_ITERS is substituted by check_x.sh\n",
        "wasm/host.js": "// check_x.sh could not instantiate its fixture\n"})
    rc, out = _run(root)
    assert "test/wasm/check_x.sh" in out, \
        "a fixture naming its own runner was counted as an invoker: %s" % out
    return "a fixture or host naming its runner is not a reference to it"


def t_a_doc_mentioning_a_runner_does_not_clear_it():
    """A LOGBOOK line and two tickets named the real orphan. History is not
    invocation, and counting it would let one paragraph hide a file forever."""
    root = _runner_tree({"wasm/check_x.sh": "#!/bin/sh\necho hi\n",
                         "wasm/NOTES.md": "check_x.sh was added today\n"})
    rc, out = _run(root)
    assert "test/wasm/check_x.sh" in out, \
        "a .md mention was counted as an invoker: %s" % out
    return "a .md mention does not count as running a runner"


def t_the_checker_NAMING_a_runner_in_its_own_source_does_not_clear_it():
    """Found by hitting it: documenting the exemption cleared the file.

    A comment in check_test_wiring.py named test/manual/try_synapse_compile.sh
    as the example of a legitimate hand-run script; the file is a .py, the scan
    read its own prose as a reference, and the only true positive in the tree
    went to zero with rc=0. wired_paths() had carried this exclusion for weeks,
    with a comment saying so, roughly a hundred lines above where the second
    scan was written.
    """
    root = _runner_tree({"wasm/check_x.sh": "#!/bin/sh\necho hi\n"})
    open(os.path.join(root, "tools", "check_test_wiring.py"), "w").write(
        "# test/wasm/check_x.sh is the example of a hand-run script\n")
    subprocess.run(["git", "add", "-A"], cwd=root, capture_output=True)
    rc, out = _run(root)
    assert "test/wasm/check_x.sh" in out, \
        "the checker's own source was counted as an invoker: %s" % out
    return "the checker naming a runner in its own source is not a reference"


def t_THIS_devtest_is_not_evidence_for_either_census():
    """The guards are built from real citations, so they name real paths.

    Every fixture below quotes a live path on purpose -- that is what makes a
    guard checkable by a reader. It also means this file mentions
    test/wasm/objlocal_slice.npy and test/manual/try_synapse_compile.sh, and
    while it was in the corpus that moved a parked .npy into `wired` and made a
    correct exemption read as STALE, which invites a deletion that re-opens the
    gap. A devtest is documentation about the check, exactly like the check's
    own source, and neither is proof that anything runs a file.
    """
    root = _runner_tree({"orphan.pas": "x\n",
                         "wasm/check_x.sh": "#!/bin/sh\necho hi\n"})
    open(os.path.join(root, "tools", "check_test_wiring_devtest.py"),
         "w").write("# test/orphan.pas and test/wasm/check_x.sh, as fixtures\n")
    subprocess.run(["git", "add", "-A"], cwd=root, capture_output=True)
    rc, out = _run(root)
    assert "test/orphan.pas" in out, \
        "the devtest's prose was counted as wiring a subject: %s" % out
    assert "test/wasm/check_x.sh" in out, \
        "the devtest's prose was counted as naming a runner: %s" % out
    return "this check's own devtest is evidence for neither census"


def t_since_reports_a_runner_THIS_push_added_that_nothing_names():
    """The cheap half, landing on the agent who still has the oracle in head.

    The census answers slowly and addresses nobody; this arm caught the real
    case at the moment it was created rather than after a suite printed green
    one check smaller than its own directory.
    """
    root, base = _committed_tree("all:\n\techo hi\n", [], [])
    full = os.path.join(root, "test", "wasm", "check_new.sh")
    os.makedirs(os.path.dirname(full), exist_ok=True)
    open(full, "w").write("#!/bin/sh\necho hi\n")
    rc, out = _run_since(root, base)
    assert "test/wasm/check_new.sh" in out, \
        "a runner added by this push and named by nothing was missed: %s" % out
    assert "THIS PUSH ADDS" in out and "NAMES" in out, out
    assert rc == 1, out
    return "a runner added by this push that nothing names fails the gate"


TESTS = [t_a_commented_mention_does_not_wire_a_file,
         t_a_hash_comment_inside_a_recipe_body_does_not_wire,
         t_a_real_rule_still_wires,
         t_a_trailing_comment_is_still_counted_and_that_is_deliberate,
         t_a_makefile_wired_exemption_is_hard_stale,
         t_a_missing_file_is_hard_stale,
         t_a_tools_only_mention_is_ADVISORY_not_stale,
         t_the_advisory_cites_its_evidence,
         t_an_advisory_alone_does_not_fail_the_check,
         t_a_real_unwired_file_still_fails,
         t_a_reasonless_exemption_is_still_refused,
         t_a_variable_truncated_path_does_not_blanket_its_directory,
         t_a_bare_stem_in_the_same_script_credits_that_file_only,
         t_a_same_stem_path_component_elsewhere_does_not_credit,
         t_a_glob_over_a_directory_still_blankets_it,
         t_a_search_path_flag_still_blankets_its_directory,
         t_the_checker_does_not_scan_its_own_source,
         t_stem_evidence_reaches_direct_children_only,
         t_since_names_a_test_THIS_push_added_and_did_not_wire,
         t_since_ignores_an_orphan_that_was_ALREADY_there,
         t_since_passes_when_the_new_test_IS_wired,
         t_since_that_cannot_resolve_its_rev_is_NOT_a_pass,
         t_since_refuses_a_COMMITTED_elf_under_test,
         t_since_refuses_an_UNTRACKED_elf_too,
         t_an_elf_named_like_nothing_is_still_caught,
         t_a_text_test_file_is_not_reported_as_a_binary,
         t_an_exempted_elf_is_let_through,
         t_a_park_on_a_live_ticket_covers_a_whole_directory,
         t_a_park_is_printed_not_silently_passed,
         t_a_park_whose_ticket_CLOSED_is_refused,
         t_a_park_naming_no_ticket_at_all_is_refused,
         t_a_park_with_no_reason_is_refused_like_any_exemption,
         t_a_runner_named_by_nothing_is_reported,
         t_a_runner_named_by_a_sibling_is_not_reported,
         t_a_directory_park_does_NOT_cover_a_runner,
         t_an_exact_exemption_DOES_cover_a_runner,
         t_a_fixture_POINTING_BACK_at_its_runner_does_not_clear_it,
         t_a_doc_mentioning_a_runner_does_not_clear_it,
         t_the_checker_NAMING_a_runner_in_its_own_source_does_not_clear_it,
         t_since_reports_a_runner_THIS_push_added_that_nothing_names,
         t_THIS_devtest_is_not_evidence_for_either_census]


def main():
    rc = 0
    print("check-test-wiring devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("check-test-wiring OK" if rc == 0 else "check-test-wiring BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
