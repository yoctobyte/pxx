#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""How much room a filesystem has left -- in BYTES and in INODES, and in RUNS.

Neither tools/twatch.py nor tools/testmgr.py ever asked the filesystem how much
room it had: no statvfs, no shutil.disk_usage, no df, and no tstate row carrying
either number. So when seven went dark for ten hours on 2026-09-07 the archive
recorded ~290 x `infra ... no report (rc=1)` and nothing that could tell a full
disk from a code bug, and settling it needed a human on the box with `df -i`.

**BYTES ALONE WOULD NOT HAVE CAUGHT IT, AND WOULD HAVE POINTED THE WRONG WAY.**

    $ df -h /tmp                          $ df -i /tmp
    tmpfs  47G  4.1G  43G   9% /tmp       tmpfs  1048576  1048568  8  100% /tmp

Nine percent full, eight inodes left, every mkdir returning ENOSPC. A guard
built on `shutil.disk_usage` or on `f_bavail` reports a healthy box during the
exact outage it was added for -- a guard that cannot fail. Hence: both numbers,
always, or this reproduces the gap it closes.

## The unit is RUNS, not percent -- because percent does not travel

The obvious threshold is a percentage, and it is wrong here for a reason the
group's own history makes concrete: seven's /tmp is a 1,048,576-inode **tmpfs**
and plexus's is a 6,283,264-inode ext4 on a real 94G disk. "10% free" is 105k
inodes on one box and 628k on the other, i.e. about eleven tier runs versus
about sixty-nine. The number that means the same thing on both is **how many
more runs fit**, because consumption is denominated in runs -- roughly 10k
inodes each, measured on seven (~9,070 for a full tier's log dir alone).

That denominator is itself a correction paid for once already. The producer
ticket first quoted ~11,170 inodes/hour from two readings and predicted a date;
a third reading three hours later was byte-identical to the second, because no
tier had run in between. Consumption tracks tier runs, not the clock: a busy day
reaches the ceiling sooner and a quiet weekend never does. So a per-hour rate,
or a date derived from one, fails in the direction that looks like safety on
exactly the quiet days when nobody is checking.

**RAW NUMBERS ON THE ROW, JUDGEMENT SEPARATELY.** probe() records what the
filesystem said; runs_left() and low() interpret it. A future reader with a
better per-run figure can re-derive the judgement from the archive, which they
cannot do if only a verdict was stored.

## f_files == 0 means "no inode limit", NOT "no inodes left"

btrfs, ZFS and some overlay/network filesystems allocate inodes dynamically and
report `f_files = f_favail = 0`. Read naively that is 0 free of 0 total, which
formats as 100% exhausted -- a permanent false alarm, and a false alarm is how a
field gets learned-around and then ignored on the day it is right. Those
filesystems get `inodes_total: None`, and every consumer here treats None as
"this resource is not rationed on this filesystem" rather than as zero.
"""
import os

# Inodes one tier run consumes under TESTTMP, order of magnitude. Measured on
# seven 2026-09-08 by frank-seven: /tmp/testmgr-* log dirs clustered at ~9,070
# files each for the larger (full-tier) ones, plus ~678 per tstate-at.* -- so
# ~10k is the round figure for a full. A quick tier is far cheaper (measured on
# plexus 2026-09-10: 67 inodes per log dir), which is why this is a CEILING used
# to answer "how many more runs fit", never an estimate of any one run.
RUN_INODES = 10000
# Bytes per run, same provenance: the scratch dir was ~375 MB when the orphan
# sweep was written, and log dirs ran 392 MB across 128 of them (~3 MB each).
RUN_BYTES = 400 * 1024 * 1024
# Refuse to start a run with less than this much room. Three, not one: a run
# that starts on the last unit of headroom fails partway through and reports a
# RED, which is worse than not starting -- the failure gets attributed to the
# sources. Three leaves room for the run plus the two that will be racing it.
MIN_RUNS = 3


def probe(path):
    """statvfs `path`. Returns the four raw numbers, or None if it cannot ask.

    None is a real answer and is not an error: a caller records the absence
    rather than a zero, because a zero here is indistinguishable from a full
    filesystem and would raise the alarm this exists to make trustworthy.
    """
    try:
        s = os.statvfs(path)
    except OSError:
        return None
    # f_frsize is the fragment size and is what f_bavail counts in; f_bsize is
    # the preferred I/O block size and is NOT the same thing on every fs.
    frsize = s.f_frsize or s.f_bsize or 4096
    limited = bool(s.f_files)          # see the module docstring
    return {
        "bytes_free": int(s.f_bavail) * frsize,
        "bytes_total": int(s.f_blocks) * frsize,
        # f_favail (available to an unprivileged process), not f_ffree (free in
        # total) -- the daemon is not root, and the reserved pool is not room it
        # can use. Same reason bytes use f_bavail rather than f_bfree.
        "inodes_free": int(s.f_favail) if limited else None,
        "inodes_total": int(s.f_files) if limited else None,
    }


def row(path, prefix="fs_"):
    """probe(), flattened into archive fields. Bytes in MB, inodes raw.

    MB because a run row is read by humans and a byte count of a 94G filesystem
    is eleven digits of noise; inodes raw because the interesting magnitudes are
    already small and rounding them hides the approach to a hard ceiling.
    """
    h = probe(path)
    if h is None:
        # Present-and-null, never absent. An absent key reads as "this version
        # did not record it"; an explicit null reads as "it was asked and could
        # not answer", and only the second is true here.
        return {prefix + k: None for k in
                ("bytes_free_mb", "bytes_total_mb", "inodes_free", "inodes_total")}
    return {
        prefix + "bytes_free_mb": h["bytes_free"] // (1024 * 1024),
        prefix + "bytes_total_mb": h["bytes_total"] // (1024 * 1024),
        prefix + "inodes_free": h["inodes_free"],
        prefix + "inodes_total": h["inodes_total"],
    }


def runs_left(h, run_inodes=RUN_INODES, run_bytes=RUN_BYTES):
    """How many more tier runs fit, by the SCARCER of the two resources.

    Returns (n, which). `which` names the binding resource, which is the whole
    point: on 2026-09-07 bytes said 43G free and inodes said eight. A caller
    that prints only `n` reproduces the ambiguity this module exists to remove.

    None when nothing can be said (no probe, or a filesystem that rations
    neither) -- distinct from 0, which is a measurement.
    """
    if h is None:
        return (None, None)
    cand = [(h["bytes_free"] // max(run_bytes, 1), "bytes")]
    if h["inodes_total"] is not None:
        cand.append((h["inodes_free"] // max(run_inodes, 1), "inodes"))
    return min(cand) if cand else (None, None)


def low(h, min_runs=MIN_RUNS, **kw):
    """The reason this filesystem is too tight to start a run, or None.

    A string rather than a bool so the caller can put the NUMBER in the log. An
    alarm that says "disk low" costs a human a trip to the box, which is the
    cost this whole group is trying to remove.
    """
    n, which = runs_left(h, **kw)
    if n is None or n >= min_runs:
        return None
    if which == "inodes":
        return ("only %d inode(s) free of %d -- about %d more run(s); bytes are "
                "fine (%d MB free), which is why a bytes-only check would pass"
                % (h["inodes_free"], h["inodes_total"], n,
                   h["bytes_free"] // (1024 * 1024)))
    return ("only %d MB free of %d -- about %d more run(s)"
            % (h["bytes_free"] // (1024 * 1024),
               h["bytes_total"] // (1024 * 1024), n))


def describe(path):
    """One log line. Always names both resources, even when both are healthy.

    Deliberately not silent-when-fine: `hosts.json` already carries cpu,
    sockets, cores, threads, mhz_max, mem_total_kb, kernel, gcc, governor and
    turbo, and its silence on disk was read for months as "disk is not a
    variable here" rather than "nobody added it". A fingerprint detailed enough
    to look complete is read as having considered what it omits.
    """
    h = probe(path)
    if h is None:
        return "%s: cannot statvfs" % path
    n, which = runs_left(h)
    ino = ("%d/%d inodes" % (h["inodes_free"], h["inodes_total"])
           if h["inodes_total"] is not None else "inodes unlimited")
    return ("%s: %d MB free of %d, %s, ~%s more run(s)%s"
            % (path, h["bytes_free"] // (1024 * 1024),
               h["bytes_total"] // (1024 * 1024), ino,
               "?" if n is None else n,
               " (%s-bound)" % which if which else ""))


if __name__ == "__main__":
    import sys
    for p in (sys.argv[1:] or ["/tmp"]):
        print(describe(p))
        h = probe(p)
        why = low(h)
        if why:
            print("  LOW: %s" % why)
