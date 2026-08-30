# Licensing Concerns

> **STATUS: SUPERSEDED — the licensing question was decided, and this page
> records the deliberation, not the position.**
>
> The authority is **[LICENSE.md](../../LICENSE.md)** (the per-directory map)
> and the `SPDX-License-Identifier` header in every source file. In brief:
> **MPL 2.0** for `compiler/**` and `tools/**`, **zlib** for the runtime and
> libraries (`compiler/builtin/**`, `lib/rtl`, `lib/pcl`, `lib/crtl`,
> `lib/asmcore`), **0BSD** for `examples/**`, **CC BY 4.0** for `docs/**`.
>
> Owner, 2026-08-30: *"we decided about the license long ago. i think that was
> stale info."* And long ago is accurate: the decision is dated **2026-07-02**
> in `done/task-license-mpl2-rollout` (*"Decision (final)"*), which is **eight
> weeks** before this page was found still saying the opposite. That ticket's
> own step 3 was *"update README.md License section (currently says no license
> yet)"* — the README was updated and this page was not, which is how a rollout
> leaves one page behind: the checklist named the file it knew about.
>
> **Two sections below are still live** and are marked as such: *Authorship, AI
> Assistance, And Future Forks*, and *Source-Available, Not Open Source*. Every
> other section — the "no license yet" position, the survey of license families,
> and the closing recommendation — describes a question that has been answered
> the other way, and is kept only as the record of how the split was reached.
>
> **Why this was not simply deleted.** The reasoning behind the zlib/MPL split
> is worth more than the file it sits in: the runtime is zlib *because it is
> embedded into every binary the compiler produces*, so programs built with pxx
> carry no obligations from the toolchain. Deleting the deliberation would leave
> the conclusion with no recorded why.
>
> Kept for the same reason the strike had to happen at all: this page said the
> repository grants no license while the repository granted four, and it linked
> to `LICENSE.md` as *"the current public notice"* — pointing at its own
> refutation.
> [[decide-the-licensing-page-says-no-license-yet-and-the-repo-has-one]]

## HISTORICAL — Current Position: No License Yet

> Superseded. The repository is licensed; see the banner above. Retained as the
> record of the position that held before the split was adopted.

The repository currently grants no open-source, free-software, commercial, or
other public license.

That means default copyright rules apply: the author retains rights, and public
visibility on GitHub should not be read as permission to copy, modify,
redistribute, sublicense, sell, or otherwise rely on the code beyond what
applicable law independently allows. GitHub's platform terms may allow viewing
and forking inside GitHub, but that is not the same thing as a project license.

This is the safest temporary position if the intended message is:

- the code may be read and discussed;
- the project is still being researched;
- no one should assume production-readiness;
- no one should infer legal rights from public repository visibility.

The current public notice is [LICENSE.md](../LICENSE.md).

## STILL LIVE — Authorship, AI Assistance, And Future Forks

> Not superseded. The licensing decision settled what rights are granted; it did
> not settle how the project talks about AI-assisted authorship or about forks,
> and those are still open public-messaging questions. The one sentence below
> that the decision DID overtake is called out at the end of the section.

The project should be candid that much of the code and documentation was
created with AI assistance. That does not mean the repository is ownerless or
abandoned. A human author directed the work, selected what to keep, edited it,
integrated it, tested it, and published it as this project.

The intended public message is:

- AI assistance is acknowledged, not hidden;
- the current repository still has a human maintainer;
- public visibility is not a public-domain dedication;
- no one should infer a right to relicense the repository just because parts of
  it were AI-assisted.

At the same time, the long-term attitude toward forks should be welcoming. The
author is not trying to prevent the code from ever becoming useful elsewhere.
It would be acceptable, in principle, for someone to maintain a serious fork
under a familiar license such as MIT, BSD, GPL, LGPL, or AGPL, provided that
permission is made explicit first.

The important boundary is responsibility. If a fork is released under its own
license, it should be clearly maintained as that fork's codebase. Its
maintainers should stand behind their license choice, changes, release claims,
and any expectations they create around support, safety, or fitness for use.

~~This is a statement of intent, not a present license grant. The current
repository remains unlicensed until a license or written permission says
otherwise.~~

> **Struck.** The repository IS licensed. A fork under MIT/BSD/GPL/LGPL/AGPL no
> longer needs permission asked first — the MPL 2.0 and zlib grants already say
> what may be done. The paragraphs above about *responsibility* — a fork
> standing behind its own license, changes and release claims — are unaffected
> and still the intent.

## STILL LIVE — Source-Available, Not Open Source

> Not superseded, though it now reads as background rather than as a live
> option. The distinction it draws is correct and worth a reader understanding;
> the project simply landed on the open-source side of it. Kept because
> "source-available" and "open source" are still confused constantly, and
> because the reasoning is what makes the zlib/MPL choice legible.

If the project grants narrow rights such as "research only",
"non-commercial only", "evaluation only", or "do not use for important work",
then the correct category is source-available, not open source.

Open-source licenses, in the OSI sense, cannot restrict fields of use. A license
that prohibits commercial use, production use, security-sensitive use,
infrastructure use, or other categories of use may be reasonable for this
project, but it should not be described as open source.

## HISTORICAL — Existing License Families To Consider

> Superseded. This survey was written to choose between narrow source-available
> licenses; the project chose open-source licenses instead. Retained because the
> reasoning about field-of-use restrictions is the argument that was weighed and
> rejected, and a reader who wonders "why not PolyForm?" deserves the answer.

### PolyForm Strict

PolyForm Strict appears closest to a narrow "source-available but not open"
position. Its published summary permits use, but not modification or
distribution, and limits the permission to non-commercial purposes.

This may be appropriate if the project wants to allow limited local
experimentation without allowing forks, modified redistribution, or commercial
use.

Concern: it may still grant more operational "use" permission than desired for
an experimental compiler that the author does not recommend for important work.

### PolyForm Noncommercial

PolyForm Noncommercial is broader. Its published summary permits
non-commercial use, modification, and distribution.

This may be useful if the project wants academic, hobby, or community forks and
patches under non-commercial terms.

Concern: it is probably too permissive for the current stated concern, because
it allows non-commercial modified redistribution.

### Functional Source License / Business Source Style

Functional Source License and Business Source style licenses are
source-available licenses that later convert to an open-source license, such as
MIT or Apache 2.0, after a fixed delay.

This may be useful if the project wants a planned path from restricted
availability to open source.

Concern: these licenses are designed mostly around delayed openness and
commercial free-riding, not around "still researching", "unsafe for important
use", or "no rights granted yet".

### Custom Research And Evaluation License

A custom license could say exactly what the project seems to mean:

- the code may be read;
- the code may be built and run locally for research, evaluation, or education;
- no production or important use is permitted;
- no redistribution or sublicensing is permitted;
- no warranty, support commitment, patent license, or trademark license is
  granted;
- the author is not responsible for reliance on the code.

This may be the best semantic fit if the project wants to grant narrow
experimental rights instead of reserving all rights.

Concern: custom licenses create uncertainty for users and contributors. They
are harder for tools, companies, package indexes, and lawyers to recognize. If
the project goes this route, the text should be reviewed carefully before
release.

## HISTORICAL — Practical Recommendation For The Public Release

> **Superseded, and this section is the one that was actively misleading.** It
> recommends keeping the no-license/all-rights-reserved notice. That advice was
> overtaken by the decision it was written to inform, and it is the opposite of
> what the repository does.

For the current release, the most conservative choice is to keep the
no-license/all-rights-reserved notice unless the project explicitly wants to
grant narrow rights to run experiments.

If narrow experimental rights are desired, use a clearly named
source-available research/evaluation license rather than an open-source license.
Do not call the project open source unless and until it uses an actual
open-source license.
