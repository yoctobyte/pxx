#!/usr/bin/env python3
"""devtest: stub_track() — an auto-filed stub must never route SILENTLY.

Track T is the default owner of a stub no other lane can be shown to own. That
routing is fine; expressing it as an ABSENT `track:` line was not. The ranker
treats "no track" and "track: T" identically, so a fallback arrived in T's
queue indistinguishable from a real T finding, with nothing on its face to
prompt a re-lane. `regression-tools-devtest-00-2` is the worked example: no
track line, no explanation, and T's only by luck.

So the invariant this guards is not "what letter" but "the letter is stated AND
the reason is stated" — for every path out of the function.
"""
import os, sys, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

fails = []
checks = 0


def check(cond, what):
    global checks
    checks += 1
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)


def main():
    # Every stub carries a track AND a note, on every path. This is the whole
    # point: a silent route is the defect, whatever letter it picks.
    cases = [
        ({"status": "fail", "src": "test/cxtensa_obj.c"}, "a C source"),
        ({"status": "fail", "src": ""}, "an empty source"),
        ({"status": "fail"}, "a missing source key"),
        ({"status": "timeout", "src": "test/foo.pas"}, "a timeout with a source"),
        ({"status": "timeout"}, "a timeout with no source"),
        ({"status": "fail", "src": "test/nothing_maps_here.xyz"}, "an unmappable source"),
    ]
    for j, desc in cases:
        track, note = tw.stub_track(j)
        check(bool(track) and track.strip() == track and len(track) <= 3,
              "%s yields a usable track letter (%r)" % (desc, track))
        check(note.strip().startswith(">") and note.endswith("\n\n"),
              "%s yields a blockquote hedge" % desc)

    # A timeout is T's REGARDLESS of what its source path would have guessed --
    # the path says what the job compiles, not what went wrong.
    t_pas, note = tw.stub_track({"status": "timeout", "src": "test/foo.pas"})
    check(t_pas == "T", "a timeout does not inherit its source's lane")
    check("TIMED OUT" in note, "the timeout note says WHY it is T")

    # A guessable source still routes where it always did: no behaviour change,
    # only the silence removed.
    for src in ("test/cxtensa_obj.c", "test/foo.pas"):
        want = tw.guess_track(src)
        if want:
            got, note = tw.stub_track({"status": "fail", "src": src})
            check(got == want,
                  "%s still routes to %s as before" % (src, want))
            check("guessed" in note.lower(),
                  "%s is marked as a GUESS, not a finding" % src)

    # The fallback must say it is a fallback. A reader who cannot tell a
    # defaulted lane from a determined one is the whole failure mode.
    _, note = tw.stub_track({"status": "fail", "src": ""})
    check("FALLBACK" in note, "the no-source note calls itself a FALLBACK")
    check("no test source" in note,
          "the no-source note says the source was missing")
    _, note2 = tw.stub_track({"status": "fail", "src": "test/nothing.xyz"})
    check("nothing.xyz" in note2,
          "an unmappable source is quoted back so the reader can check it")
    check(note != note2,
          "'no source' and 'unmappable source' are distinguishable")

    # Regression guard for the shape that started this: the old code emitted
    # NOTHING for these, and nothing is what made it invisible.
    for j in ({"status": "fail", "src": ""}, {"status": "timeout"}):
        track, note = tw.stub_track(j)
        check(track == "T" and len(note) > 80,
              "the previously-silent path %r now explains itself" % (j,))

    print("\n%s (%d checks, %d failed)"
          % ("FAIL" if fails else "PASS", checks, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
