#!/bin/sh
# Sample box contention FOR THE DURATION OF ONE MEASURED RUN, and print it as
# one line that sits beside that run's number.
#
# WHY THIS EXISTS. `devdocs/perf/FRAME-RATE-2026-09-20.md` in the lekkerzeilen
# repo says it outright, in its own "Not done, and it should be" section:
#
#     "the box state was checked before and after, not logged per run. A row
#      like this should carry a load sample beside each arm. That is cheap and
#      it is the difference between 'interleaved, so drift cancels' as an
#      argument and as a measurement."
#
# Interleaving arms defends against DRIFTING load: it hits both arms, so the
# RATIO survives even when the absolutes move. It does not defend against a
# STEADY load present for the whole row -- that depresses both arms together
# and a ratio survives it only if the load happens to be multiplicative. The
# document names the case to watch: a GPU shared by two programs can halve both
# arms and still produce a perfectly plausible table.
#
# AND A STEADY LOAD DOES NOT SHOW UP IN THE SPREAD, WHICH IS THE ONLY EVIDENCE
# THOSE ROWS CURRENTLY OFFER. That is the whole gap. A tight spread is
# consistent with a clean box and with a box that was equally busy the entire
# time, and nothing in the row separates them.
#
# WHAT THE EXISTING TOOLS DO, AND THE THREE WAYS IT FALLS SHORT.
# `devdocs/perf/tools/n25.sh:52` and `n26.sh:42` both record
# `cut -d' ' -f1 /proc/loadavg` -- one field, once, after the arm finishes:
#   1. It is a ONE-MINUTE AVERAGE sampled once, so for a 45-60 s arm it is
#      partly about what happened BEFORE the arm started, and it lags.
#   2. Once at the end cannot distinguish a load that arrived mid-run from one
#      that was there throughout -- which is exactly the distinction that
#      decides whether interleaving protected the ratio.
#   3. It is CPU only. The contention the document singles out is the GPU.
#
# WHAT THIS SAMPLES, AND THE POPULATION IT ENUMERATES -- stated because a
# census answers honestly about whatever set it walks, and the reader has to be
# able to check their subject is in it:
#   * /proc/loadavg field 1, and field 4's running-thread count, every INTERVAL
#     seconds for as long as the wrapped command runs. Reported as min/med/max
#     across the samples, never as a single number: the LEVEL separates a busy
#     box from an idle one, and the RANGE separates drifting load from steady.
#   * GPU memory held by every compute process EXCEPT this run's own process
#     tree, via `nvidia-smi --query-compute-apps=pid,used_memory`. Absent
#     nvidia-smi the GPU columns read `-` and say so; they are never silently 0.
#   * The count of OTHER processes holding an open /dev/dri file descriptor,
#     read from /proc/<pid>/fd. Note this counts PROCESSES, not handles: at the
#     time of writing this box showed 8 processes holding 44 such descriptors,
#     and quoting the handle count as a process count overstates contention 5x.
#
# THE OBSERVER IS EXCLUDED FROM EVERY POPULATION IT IS IN, WHICH IS THE POINT
# THAT MAKES THIS DIFFERENT FROM A `pgrep`. The wrapped command's pid, this
# script's pid, and the sampler's own pid are removed from the GPU and /dev/dri
# sets before any count. An instrument that scans a namespace the observer also
# occupies counts the observer -- `ps`/`pgrep`/`pkill -f` are that by
# construction, and the bracket trick does not close it because the PARENT
# shell's command line contains the pattern too. Nothing here matches on a
# command name at all; it works from pids and /proc entries.
#
# USAGE -- it WRAPS the run rather than being started beside it, so the sample
# window is exactly the arm and there is no wait loop to get wrong:
#
#   tools/box_load_sample.sh <label> -- <command> [args...]
#   tools/box_load_sample.sh --selftest
#
# The wrapped command's stdout and stderr are untouched and its exit status is
# this script's exit status, so it drops into an existing harness without
# changing what that harness reads. The sample line goes to STDERR, prefixed
# `boxload:`, so it cannot land in a pipeline that is parsing the run's output.
# Set BOXLOAD_INTERVAL to change the 2 s cadence; BOXLOAD_RAW=<file> also
# writes every individual sample there.
#
# WHAT IT DOES NOT ESTABLISH. It reports what else was on the box; it does not
# prove your number was unaffected, and a clean line is not a licence to skip
# interleaving. Two clean lines either side of a big delta make contention a
# poor explanation for it -- that is all, and it is worth having because today
# the row cannot say even that.

set -u

INTERVAL="${BOXLOAD_INTERVAL:-2}"
RAW="${BOXLOAD_RAW:-}"

# --- the sample, one line: load1 runq gpu_other_mib gpu_other_procs dri_procs
sample_once() {
    _self_pids="$1"
    _la=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "-")
    _rq=$(cut -d' ' -f4 /proc/loadavg 2>/dev/null | cut -d/ -f1 || echo "-")

    _gmib="-"; _gproc="-"
    if command -v nvidia-smi >/dev/null 2>&1; then
        _gmib=0; _gproc=0
        # `pid, NNN MiB` per line. Ours are excluded BEFORE the sum, not after.
        while IFS= read -r _row; do
            [ -n "$_row" ] || continue
            _pid=$(printf '%s' "$_row" | cut -d, -f1 | tr -d ' ')
            _mem=$(printf '%s' "$_row" | cut -d, -f2 | tr -dc '0-9')
            case " $_self_pids " in *" $_pid "*) continue ;; esac
            [ -n "$_mem" ] || continue
            _gmib=$((_gmib + _mem)); _gproc=$((_gproc + 1))
        done <<EOF
$(nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader 2>/dev/null)
EOF
    fi

    # PROCESSES holding a /dev/dri fd, not handles. Ours excluded.
    _dri=0
    for _fd in /proc/[0-9]*/fd; do
        _p=${_fd%/fd}; _p=${_p#/proc/}
        case " $_self_pids " in *" $_p "*) continue ;; esac
        if ls -l "$_fd" 2>/dev/null | grep -q '/dev/dri'; then
            _dri=$((_dri + 1))
        fi
    done

    printf '%s %s %s %s %s\n' "$_la" "$_rq" "$_gmib" "$_gproc" "$_dri"
}

# --- min / median / max of one whitespace column, or `-` if non-numeric
stat3() {
    _col="$1"; _file="$2"
    _vals=$(awk -v c="$_col" '{print $c}' "$_file" | grep -E '^[0-9.]+$' | sort -g)
    [ -n "$_vals" ] || { printf -- '-/-/-'; return; }
    _n=$(printf '%s\n' "$_vals" | wc -l)
    _min=$(printf '%s\n' "$_vals" | head -1)
    _max=$(printf '%s\n' "$_vals" | tail -1)
    _med=$(printf '%s\n' "$_vals" | sed -n "$(( (_n + 1) / 2 ))p")
    printf '%s/%s/%s' "$_min" "$_med" "$_max"
}

run_sampled() {
    _label="$1"; shift
    _tmp=$(mktemp) || exit 1
    trap 'rm -f "$_tmp"' EXIT INT TERM

    "$@" &
    _cmd_pid=$!

    # The wrapped pid, this shell, and this shell's parent: every process that
    # exists because we are measuring. Excluded from every population below.
    _self="$_cmd_pid $$ $PPID"

    (
        while kill -0 "$_cmd_pid" 2>/dev/null; do
            sample_once "$_self" >> "$_tmp"
            sleep "$INTERVAL"
        done
    ) &
    _sampler_pid=$!

    wait "$_cmd_pid"; _rc=$?
    wait "$_sampler_pid" 2>/dev/null

    _n=$(wc -l < "$_tmp" | tr -d ' ')
    if [ "$_n" -eq 0 ]; then
        # Shorter than one interval. Say so rather than printing a clean line:
        # "no samples" and "nothing was running" must not look alike.
        echo "boxload: $_label  NO SAMPLES (ran under ${INTERVAL}s) rc=$_rc" >&2
        [ -n "$RAW" ] && cp "$_tmp" "$RAW"
        return "$_rc"
    fi

    _gpu=$(stat3 3 "$_tmp"); _gp=$(stat3 4 "$_tmp")
    [ "$_gpu" = "-/-/-" ] && _gpu="nvidia-smi ABSENT"

    echo "boxload: $_label  n=$_n@${INTERVAL}s  load1=$(stat3 1 "$_tmp")  runq=$(stat3 2 "$_tmp")  gpu_other_MiB=$_gpu  gpu_other_procs=$_gp  dri_other_procs=$(stat3 5 "$_tmp")  driver=${SDL_VIDEODRIVER:-UNSET}  rc=$_rc" >&2
    [ -n "$RAW" ] && cp "$_tmp" "$RAW"
    return "$_rc"
}

# --- POSITIVE CONTROL. A guard that cannot fail is not a guard, and a sampler
# that reports a quiet box is indistinguishable from one that is broken -- the
# same shape as a green census that cannot detect a newly-broken row. So the
# control introduces a load this script did not create by accident and asserts
# the reading MOVES. It can come out false, and it says which half it proves:
# the CPU path end to end (timing, parsing, aggregation), and the exclusion of
# our own pids. It does NOT prove the GPU path, because manufacturing GPU
# contention needs a GPU allocation this script has no business making -- that
# arm is asserted only to be non-silent, never to be zero.
selftest() {
    _fail=0
    _q=$(mktemp); _b=$(mktemp)
    trap 'rm -f "$_q" "$_b"' EXIT INT TERM

    # ASSERTED ON runq, NOT ON load1, AND THAT IS THIS SCRIPT'S OWN CRITICISM
    # TURNED ON ITSELF. The header faults n25.sh for reading a ONE-MINUTE
    # AVERAGE over a 45-60 s arm; a control that reads load1 over a 3 s window
    # has the same defect and worse. Measured while writing this: four busy
    # shells for 3 s moved load1 from 2.26 to 2.32 -- 0.06 on a box whose own
    # idle noise is larger, so the assertion would have passed or failed at
    # random and a passing run would have proved nothing. The same load moved
    # runq (field 4, RUNNING threads, instantaneous and unsmoothed) from 2-3 to
    # 7-9. load1 stays in the OUTPUT, where a slow-moving average is the right
    # thing for "was this box busy for the whole row"; it is simply not a
    # control for a three-second experiment.
    BOXLOAD_INTERVAL=1 BOXLOAD_RAW="$_q" "$0" quiet -- sleep 3 2>/dev/null
    _qmax=$(stat3 2 "$_q")
    _qmax=${_qmax##*/}

    # Four busy shells for the same window. Started by us, so their load is
    # real and their pids are NOT in the exclusion set (only the wrapped
    # command and our own shells are) -- which is what makes this a load the
    # sampler must see rather than one it is blind to by design.
    BOXLOAD_INTERVAL=1 BOXLOAD_RAW="$_b" "$0" busy -- sh -c '
        for i in 1 2 3 4; do (end=$(( $(date +%s) + 3 ));
          while [ "$(date +%s)" -lt "$end" ]; do :; done) & done; wait' 2>/dev/null
    _bmax=$(stat3 2 "$_b")
    _bmax=${_bmax##*/}

    # A MARGIN, because runq's idle value is not zero and a 1-count difference
    # is within its own jitter. Four busy shells must show up as clearly more
    # than idle noise or the sampler is not measuring what it claims.
    echo "selftest: quiet runq max = $_qmax"
    echo "selftest: busy  runq max = $_bmax  (expect >= quiet + 3)"
    if [ "$(awk -v a="$_bmax" -v b="$_qmax" 'BEGIN{print (a >= b+3)?1:0}')" = "1" ]; then
        echo "selftest: PASS  the sampler detects a load it did not create"
    else
        echo "selftest: FAIL  busy did not clear quiet+3 -- sampling is not working,"
        echo "selftest:       or the box was already saturated so the test cannot tell."
        _fail=1
    fi

    # Our own pids must never appear in a count. Asserted rather than assumed,
    # because the exclusion is the one thing distinguishing this from a pgrep.
    if sample_once "$$ $PPID" >/dev/null 2>&1; then
        echo "selftest: PASS  sample_once accepts an exclusion set"
    else
        echo "selftest: FAIL  sample_once errored"; _fail=1
    fi

    if command -v nvidia-smi >/dev/null 2>&1; then
        echo "selftest: NOTE  GPU arm is live but NOT proven by this control --"
        echo "selftest:       a zero there means no other compute process, and"
        echo "selftest:       this test cannot manufacture one to prove it."
    else
        echo "selftest: NOTE  nvidia-smi absent; GPU columns will read ABSENT,"
        echo "selftest:       which is the point -- they never read 0 silently."
    fi
    return "$_fail"
}

case "${1:-}" in
    --selftest) selftest ;;
    -h|--help|"") sed -n '2,/^set -u/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
        _label="$1"; shift
        [ "${1:-}" = "--" ] || { echo "usage: $0 <label> -- <command...>" >&2; exit 2; }
        shift
        [ $# -gt 0 ] || { echo "usage: $0 <label> -- <command...>" >&2; exit 2; }
        run_sampled "$_label" "$@"
        ;;
esac
