#!/bin/sh
# hostcheck.sh — is this BOX lying to us right now?
#
# Written 2026-08-25, after two failures that were neither of them code defects
# and both of which reported success-shaped output while broken:
#
#   * Track T went blind for three days. The daemon was alive, `systemctl` said
#     active, `trackt health` said OK -- and every native run was being torn
#     down at the 3600s deadline by one test hanging in GTK's at-spi bridge,
#     publishing a CONTENTLESS RED each time. Liveness was checked; verdicts
#     were not. That is the error this script exists to make impossible.
#   * DNS resolved through a router forwarder dropping ~40% of queries in
#     bursts, for hours, while the NetworkManager profile claimed 8.8.8.8. The
#     profile had been corrected and the live device never reapplied.
#
# Both share a shape: the thing reporting is not the thing doing. So every
# check here compares a CLAIM against the SYSTEM'S OWN RECORD, and every check
# is bounded in time -- a health check that can hang is a second outage.
#
# Cheap and deterministic on purpose: no model, no tokens, safe to run every
# 20 minutes from cron. Prints one line per check; exits 1 if anything FAILed.
#
#   OK    nothing to do
#   WARN  worth a human eye, not urgent
#   FAIL  something is broken or lying; exit 1
set -u

REPO=${REPO:-/home/neo/frank1}
WATCH_CLONE=/home/neo/trackt-watch
rc=0

say()  { printf '%-6s %-12s %s\n' "$1" "$2" "$3"; }
ok()   { say OK   "$1" "$2"; }
warn() { say WARN "$1" "$2"; }
fail() { say FAIL "$1" "$2"; rc=1; }

# ---------------------------------------------------------------- Track T ---
# The verdict check, NOT the liveness check. `wall` at (or just under) the
# 3600s global deadline means the run was TORN DOWN, not completed: the report
# it published carries no usable verdict however green the tree actually is.
#
# Read tstate from ORIGIN, never from the local checkout. The local file is
# only as fresh as the last pull, and reporting your own staleness as the
# watcher's is exactly the trap CLAUDE.md warns about for `twatch --status`.
check_trackt() {
    git -C "$REPO" fetch --no-write-fetch-head -q origin 2>/dev/null

    json=
    for ref in origin/dev origin/master; do
        json=$(git -C "$REPO" show "$ref:devdocs/progress/tstate/plexus.json" \
               2>/dev/null) && [ -n "$json" ] && break
    done
    if [ -z "$json" ]; then
        fail trackt "no tstate/plexus.json on origin/dev or origin/master"
        return
    fi

    printf '%s' "$json" | python3 -c '
import json, sys, time, calendar
d = json.load(sys.stdin)
last = d.get("last") or {}
wall = last.get("wall")
date = last.get("date", "")
sha  = (last.get("sha") or "")[:12]
tier = last.get("tier", "?")
verdict = last.get("verdict", "?")

try:
    age = (time.time() - calendar.timegm(time.strptime(date, "%Y-%m-%dT%H:%M:%SZ"))) / 60.0
except Exception:
    age = None

# 3600s is the global deadline. Anything within 5s of it was killed, not run.
if wall is not None and wall >= 3595:
    print("FAIL|torn down at the %.0fs deadline (%s %s, %s) -- CONTENTLESS, "
          "T is blind" % (wall, tier, sha, verdict))
elif age is None:
    print("WARN|last run has an unparseable date: %r" % date)
elif age > 180:
    print("FAIL|no completed run for %.0f min (%s %s)" % (age, tier, sha))
elif age > 90:
    print("WARN|last completed run is %.0f min old (%s %s)" % (age, tier, sha))
else:
    print("OK|%s %s %s, wall %.0fs, %.0f min ago"
          % (verdict, tier, sha, wall if wall is not None else -1, age))
' 2>/dev/null | while IFS='|' read -r lvl msg; do
        case "$lvl" in
            OK)   ok   trackt "$msg" ;;
            WARN) warn trackt "$msg" ;;
            *)    fail trackt "$msg" ;;
        esac
    done

    # `while` above runs in a subshell, so its rc never reaches us. Re-derive.
    printf '%s' "$json" | python3 -c '
import json,sys
l=(json.load(sys.stdin).get("last") or {})
w=l.get("wall")
sys.exit(1 if (w is not None and w>=3595) else 0)' 2>/dev/null || rc=1
}

# The daemon being ALIVE is a separate, weaker fact. Report it as its own line
# so nobody again mistakes it for "Track T is working".
check_daemon() {
    if systemctl --user is-active --quiet trackt-watcher.service 2>/dev/null; then
        ok daemon "trackt-watcher.service active (liveness only, see trackt line)"
    else
        fail daemon "trackt-watcher.service NOT active"
    fi
}

# ---------------------------------------------------------------- network ---
# Compare the APPLIED device config against the PROFILE. They diverge silently
# whenever someone runs `nmcli connection modify` without `nmcli device
# reapply`, and the box then resolves through whatever DHCP handed it.
check_dns_applied() {
    command -v nmcli >/dev/null 2>&1 || { warn dns "nmcli absent, skipped"; return; }
    for dev in enp7s0 wlp8s4; do
        nmcli -g GENERAL.STATE device show "$dev" 2>/dev/null \
            | grep -q connected || continue
        applied=$(nmcli -g IP4.DNS device show "$dev" 2>/dev/null | paste -sd, -)
        con=$(nmcli -g GENERAL.CONNECTION device show "$dev" 2>/dev/null)
        [ -n "$con" ] || continue
        profile=$(nmcli -g ipv4.dns connection show "$con" 2>/dev/null | tr -d ' ')
        case "$applied" in
            *"$(printf '%s' "$profile" | cut -d, -f1)"*)
                ok dns "$dev applied=$applied matches profile" ;;
            *)
                fail dns "$dev APPLIED=$applied but PROFILE=$profile -- run: nmcli device reapply $dev" ;;
        esac
    done
}

# Prove resolution works AND is not merely slow. Both matter, and the slow case
# is the one that hides: on 2026-08-25 every unqualified lookup on this box took
# exactly 10.02s while succeeding, so nothing failed and everything crawled.
#
# Cause, worth stating because the fix looks wrong until you see it: a DNS
# search domain of `local` collides with mDNS. `.local` is reserved for
# multicast DNS, and nsswitch here is `files mdns4_minimal [NOTFOUND=return]
# dns` -- so `github.com` is tried as `github.com.local` FIRST, waits out the
# full mDNS timeout, and only then falls through to real DNS. Comparing the
# unqualified lookup against the same name with a trailing dot (which skips the
# search list entirely) isolates it in one measurement.
check_dns_resolve() {
    t0=$(date +%s%N)
    timeout 20 getent hosts github.com >/dev/null 2>&1; got=$?
    t1=$(date +%s%N)
    unq=$(( (t1 - t0) / 1000000 ))

    t0=$(date +%s%N)
    timeout 20 getent hosts github.com. >/dev/null 2>&1
    t1=$(date +%s%N)
    fqdn=$(( (t1 - t0) / 1000000 ))

    if [ "$got" -ne 0 ]; then
        fail resolve "github.com did NOT resolve within 20s"
    elif [ "$unq" -gt 2000 ] && [ "$fqdn" -lt 500 ]; then
        fail resolve "unqualified ${unq}ms vs FQDN ${fqdn}ms -- the search list is stalling; drop \`local\` from ipv4.dns-search (it is mDNS-reserved) and use via.local"
    elif [ "$unq" -gt 2000 ]; then
        fail resolve "resolution is slow: ${unq}ms unqualified, ${fqdn}ms FQDN"
    else
        ok resolve "github.com ${unq}ms (FQDN ${fqdn}ms)"
    fi
}

# ------------------------------------------------------------ environment ---
# Every `systemd-run --user` job on this box inherits the graphical session, so
# anything that opportunistically talks to a display or session bus can hang.
# a11y was merely the symptom that hung first; warn while the durable fix (strip
# the environment for test runs) is still an open Track T ticket.
check_session_env() {
    pid=$(systemctl --user show -p MainPID --value trackt-watcher.service 2>/dev/null)
    case "${pid:-0}" in ''|0) warn env "watcher not running, env not checked"; return ;; esac
    env=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null) || {
        warn env "cannot read /proc/$pid/environ"; return; }
    graphical=$(printf '%s\n' "$env" | grep -cE '^(DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS)=')
    guarded=$(printf '%s\n' "$env" | grep -cE '^(NO_AT_BRIDGE|GTK_A11Y)=')
    if [ "$graphical" -gt 0 ] && [ "$guarded" -eq 0 ]; then
        warn env "watcher inherits $graphical graphical vars, no NO_AT_BRIDGE/GTK_A11Y guard"
    elif [ "$graphical" -gt 0 ]; then
        ok env "inherits $graphical graphical vars but is guarded"
    else
        ok env "clean environment"
    fi
}

# ------------------------------------------------------------------- repo ---
# Unpushed work is work Track T cannot see, and this box has no UPS.
check_repo() {
    branch=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)
    ahead=$(git -C "$REPO" rev-list --count "origin/$branch..HEAD" 2>/dev/null || echo 0)
    dirty=$(git -C "$REPO" status --porcelain --untracked-files=no 2>/dev/null | wc -l)
    [ "$ahead" -gt 0 ] && warn repo "$branch has $ahead unpushed commit(s)" \
                       || ok repo "$branch is pushed"
    [ "$dirty" -gt 0 ] && warn repo "$dirty uncommitted file(s) -- no UPS on this box"

    behind=$(git -C "$REPO" rev-list --count origin/master..origin/dev 2>/dev/null || echo 0)
    [ "$behind" -gt 0 ] && ok sync "dev is $behind commit(s) ahead of master (sync-back pending)"
}

check_trackt
check_daemon
check_dns_applied
check_dns_resolve
check_session_env
check_repo

exit $rc
