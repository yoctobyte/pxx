# The Tale of Turbo Pascal, Delphi, and FPC

*A short, opinionated history of the Pascal lineage — trying to be fair to everyone
in it.*

## A language built to be understood

Pascal was Niklaus Wirth's, 1970 — a teaching language, designed for clarity and
structure at a time when that was a radical idea. Wirth (1934–2024) kept going:
Modula-2, then Oberon, always chasing the same thing — software you can reason about.
The irony is that the "teaching language" turned out strong enough to write
operating systems, compilers, and, decades later, this. The name itself reaches
further back, to Blaise Pascal (1623–1662), who built one of the first mechanical
calculators. The whole project is an inheritance from those two names.

## The democratization: Turbo Pascal

In 1983 a young Anders Hejlsberg wrote a Pascal compiler that Borland sold as Turbo
Pascal — for about fifty dollars. It was fast, it bundled an editor and compiler in
one screen, and it put real programming in front of anyone with a PC and pocket
money. That is the part worth remembering: for a while, the price of entry to a
serious tool was the price of a textbook. A generation learned to program on it.

## The peak: Delphi

In 1995 Borland shipped Delphi — Object Pascal, the VCL component library, and a
visual RAD IDE, with Hejlsberg as chief architect. It was, by most accounts, the
best application-development environment of its era. Delphi 3 and 4 (1997–98) were
the sweet spot: a couple hundred dollars for the Pro edition bought a tool you could
build on productively for years. Money well spent, no asterisk.

Hejlsberg left for Microsoft in 1996, where he went on to design C#, then .NET, then
lead TypeScript — one of the most consequential careers in language design, full
stop. And in 2001 Borland shipped Kylix: Delphi for Linux. It was ahead of its time,
a genuine milestone — native Pascal RAD on Linux — and it was discontinued within a
couple of years. That road-not-taken is, in hindsight, exactly the territory FPC and
Lazarus later had to rebuild from scratch.

## The drift upmarket

After Delphi 5 the center of gravity moved. The company churned — Borland became
Inprise, then Borland again, spun the tools off as CodeGear, sold them to Embarcadero
in 2008, which was itself absorbed by Idera in 2015. Each turn pushed further toward
the enterprise. Pricing climbed into four figures a year for the language and its
libraries; the free tier shrank to something you couldn't really ship with.

None of that is villainy. Modern Delphi is a capable, broad-reaching product —
desktop and mobile from a single codebase, and the kind of polished industry-standard
integration (signing, vendor SDKs, commercial component and database ecosystems) that
a serious business genuinely benefits from. For a company of real size, the license
can be money well spent. It is a rational product, aimed squarely at the customer it
chose: the enterprise.

It just stopped being aimed at the individual. The hobbyist, the student, the
craftsperson between jobs, the tinkerer who is not about to pay several thousand a
year for a tool — Turbo Pascal's original audience — was quietly priced out.

## The open line: FPC

Free Pascal started in 1993 and grew, slowly and stubbornly, into a serious
compiler: Delphi-compatible modes, and a target matrix that is frankly enormous —
many CPUs across many operating systems, far broader in raw reach than anything
commercial. Lazarus rebuilt the Delphi-style RAD experience in the open. Somewhere
around fifteen years ago the practical consensus for a lot of independent developers
had quietly settled: reach for the open lineage. Not because it always won on
features — Delphi often led there, and likely still has the better commercial-standard
integration — but on **economics and durability**. A free, openly maintained
compiler is simply a more durable thing to build a decade of code on than a toolchain
behind a renewing enterprise license. You can read it, you can keep it, no one can
take it away or price you out of your own source.

That is the trade the two halves of the family made. Delphi optimized for the
enterprise and got enterprise virtues. FPC optimized for openness and reach and got
those. Both are honest choices. They just serve different people.

---

With gratitude to all of them — Wirth and Pascal, Hejlsberg and the Borland and
Delphi engineers, and the Free Pascal community — for the language, the ideas, and
the foundation.
