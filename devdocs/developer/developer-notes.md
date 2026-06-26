# Notes

So, first off: I never could have developed this project alone. A, because of
the limits of a human lifetime, and B, because I am really not smart enough.

Having said that, I:
A. Learned a lot about compiler internals, mostly on an architectural level.
B. Learned that top-notch AI around May and June 2026 really started to perform
well on a complex project. Not just bug hunting, but active development.
I did give some guidance. Recently I ended up with a quick-and-dirty ticket
system that seems to work just fine. General steering is still needed. Apart
from that, AI solves stuff in minutes that would take me hours to study. It
also seems to have a language of its own, especially since I installed the
caveman tool. It is sometimes very shortened, and that last sentence is a good
example.

Multiple agents are working on this. I had banned Antigravity for a while
because of seriously poor performance. Gemini can write quite good and adequate
code, but Antigravity's tooling was just substandard. It kept going into loops,
examining every file in the project, or going line by line, and never seemed to
self-reflect. It let its agents go rogue until we ran out of tokens, with no
real work done apart from creating chaos. Even the other agents noticed and/or
had to clean up shit. Gemini 3.5 is fantastic, though.

Update: I unbanned Antigravity for one scoped trial — a per-target asm emitter,
clear ticket, precedent to copy, hard byte-identity gate. It delivered all four
emitters and they work (QEMU green, byte-identical bootstrap). Fast. But it
dumped everything into one monolith, duplicated files, and pointed its own tests
at the dead copies. The cleanup cost about as much as writing the emitters would
have. So I re-banned it. The point of this whole setup is to amplify my thoughts
into code, not to babysit an agent that nets zero after its own mess. Speed
doesn't matter if I have to supervise every line and refactor it after. So,
Google... stop antigoogling.

As for the project goals: wide and ambitious. That's all I can say for now.
They will probably be drawn back to earth by gravity. Pun not intended.

# Developer Notes

Rough developer notes. These are loose thoughts, not polished project
positioning.

## Warning

This project still has many bugs. Do not use it for anything important.

## What It Is

It is a compiler written in Pascal. Why Pascal? It is similar to C, and in some
ways a sort of superset of C.

The compiler supports Object Pascal, but the compiler itself is written in
linear Pascal.

The architecture is blunt: a bunch of includes combined into one monolithic
source file. I have discussed this with the agents. It is totally
counterintuitive to what a human would usually do: split it into manageable
pieces, like files. Yet AI agents insisted. They would rather grep what they
need from a known file than deal with an overly complex, well-designed file
architecture. So I let them, and it seems to work well. It is still readable
and somewhat organized, yet pretty large for a human. Then again, well
organized.

## Side Goals Already Achieved

These were not really goals, but more like side effects:

- fast compile time, assuming plenty of RAM;
- small executables: no linker step, really only what is needed.

I tried to keep those goals throughout the project, but obviously things like
memory management and everything else may take their toll.

## FPC Compliance

Yes and no.

We like to have our source be compilable by FPC, or any other Pascal compiler
for that matter. We cannot escape being a dialect of our own, even if we strive
for compatibility.

Our aim is to be lax and to fully implement modern syntax. That is quite bold,
and who defines what is fashionable? So we strive for FPC compatibility for
compiling ourselves, to bootstrap or just as sane compatibility validation.

## Features

- We compile C, and demangle the macro soup as far as possible.
- We compile Python as if it were Pascal. Pascal is the superset.

Non-goals or possible future language targets:

- C++: not a target. It is really too complicated and dependent on everything.
- Rust: sounds plausible, but there are many gotchas.
- JavaScript: sort of doable, but its HTML dependency will come bite us.
- Java: sounds doable; somewhat compatible with Object Pascal. Not a target at
  the moment.
- C#: see Java, with even more introspection and reflection issues.

All of those need sincere attention and may undermine our goals.

## Project Shape

This is an odd project with various goals. It is a research project. Hopefully
one day it will be useful; right now it is not. I tried documenting it.

This is totally vibe-coded. But where a human may walk and sometimes run,
agentic agents can run at 100 mph all day.

## Self-Hosting And Bootstrap

We are not ashamed to bootstrap. Why waste cycles on fixing bugs or crafting
features if helpful tools exist? That would be suffering in vain and a waste of
time. Compatibility is the goal.

## Frankonpiler

Franken is a multi-faceted goal:

1. cross-compile;
2. zero external dependencies on Linux or Linux-like kernels to self-host.

Windows is not a target. It is too complex for self-hosting. Windows as a
cross-compile target is obviously possible in the future. Just use WSL2. I do
not intend to port code to Windows, but if someone likes to do that, be my
guest.

## Goals

It is not trivial to set a single primary goal.

Subgoals:

- craft a Pascal compiler that is somewhat compatible with the FPC compiler.
