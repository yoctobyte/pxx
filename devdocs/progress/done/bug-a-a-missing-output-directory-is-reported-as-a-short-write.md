---
track: A
prio: 30
type: bug
blocked-by: []
summary: "An output path whose PARENT DIRECTORY does not exist takes the OutWriteShort branch in compiler.pas, which prints `a write to the output file stored fewer bytes than asked` and a four-cause checklist (free bytes, free inodes, ulimit -f, a concurrent writer) that does not contain the actual cause. The accurate message already exists forty lines further down -- `usual cause: a missing or unwritable directory in that path` -- and is unreachable for this input, because OutWriteShort is tested first and is true. So this is a BRANCH-ORDER defect, not a missing checklist item: the fix is to let the existing message win, not to add a fifth cause to a checklist that should not have printed."
status: done
owner: unassigned
---

# A missing output directory is reported as a short write

- **Type:** bug — **Track A** (`compiler/compiler.pas`, the output-artefact check).
- **Found 2026-09-27 by frankZ**, while finishing the LX6 first-silicon run.
  Inherited from `devdocs/dev/parked-patches/esp32-classic-lx6-first-silicon-run.md`,
  which is deleted now that the run is done; this ticket is where its one
  non-ESP32 finding lives.

## Repro, with its control

Both at pin v441 (`4ebfa2d047a2`), tree `5b4e7381dc`:

    $ printf 'begin\n  writeln(1);\nend.\n' > t.pas
    $ pinned t.pas <scratch>/no-such-dir/out
    pascal26: error: a write to the output file stored fewer bytes than asked: <scratch>/no-such-dir/out
      check all four -- the first is the commonest and the last is the one that fools people:
        df -h <dir>   free BYTES
        df -i <dir>   free INODES -- can hit 100% while df -h reads 9%
        ulimit -f     a file-size limit truncates at a plausible size
        another pascal26 writing THIS SAME PATH -- two writers interleave,
          and the file can then end up the RIGHT size, so its size proves nothing.
    rc=1

    $ pinned t.pas <scratch>/out          # control: same command, directory exists
    ok: <scratch>/out  [code=680B data=368B bss=34600B procs=37 codeseg=3808B]
    rc=0

The parent directory is the only thing that differs between the two rows.

## The mechanism, which is not what the symptom suggests

`compiler.pas` tests `OutWriteShort` (line ~999) **before**
`OutputArtefactLanded` (line ~1010). With no parent
directory the writes report short, so the first branch is taken and `Halt(1)`
runs — and the second branch's message,

    pascal26: error: compiled successfully but wrote no output file: <path>
      the code was generated; the artefact is not on disk or is empty.
      usual cause: a missing or unwritable directory in that path.

**is correct, is already written, and is unreachable for this input.**

That is why the original note's suggested fix — "`stat` the parent directory
and add it to the checklist" — is the wrong repair. It would add a fifth line
to a checklist that should not be printing at all, and leave the accurate
message still unreachable. **Order the branches so the specific cause is tested
before the generic one**, or have the short-write branch `stat` the parent and
defer when it is absent.

## Why it is worth the 30 and not more

It costs a reader real time and it lies in the expensive direction — a
four-item checklist reads as a *diagnosis*, and the reader goes and measures
four healthy things. Measured in the original incident: `df -h` said 90 G free,
`df -i` said 1 %, `ulimit -f` unlimited, no second writer. Nothing on the list
was the cause and the list gave no hint of that.

It is not higher because the input is a mistake (a path into a directory that
is not there), the exit code is correct, and nothing is silently wrong — only
the explanation is.

## The trap in the surrounding comment, which a fix must not disturb

The comment above this block (dated 2026-09-21) records that this checklist,
**quoted in a captured log, reads as evidence for the condition it explains**:
`test_trunc26` manufactures a short write on purpose, and when its output
appeared in a tier report two seats read the `df -h` / `df -i` lines as a
finding about the test host and nearly built a "host transient" story on it.
The compiler prints all four causes unconditionally and has checked none of
them. **Keep the causes; do not let a fix phrase any of them as an
observation** — and note that a fix here makes that comment *more* true, not
less, by ensuring the checklist only prints when a short write really happened.

## Log
- 2026-09-27 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 46083e0d4d.
