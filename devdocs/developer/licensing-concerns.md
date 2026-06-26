# Licensing Concerns

This project is public, but it is not open source yet. The current position is
that the code is visible for inspection, discussion, and research while the
project is still experimental and while the licensing decision remains open.

This document records the licensing choices under consideration and the main
concerns behind them.

## Current Position: No License Yet

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

## Authorship, AI Assistance, And Future Forks

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

This is a statement of intent, not a present license grant. The current
repository remains unlicensed until a license or written permission says
otherwise.

## Source-Available, Not Open Source

If the project grants narrow rights such as "research only",
"non-commercial only", "evaluation only", or "do not use for important work",
then the correct category is source-available, not open source.

Open-source licenses, in the OSI sense, cannot restrict fields of use. A license
that prohibits commercial use, production use, security-sensitive use,
infrastructure use, or other categories of use may be reasonable for this
project, but it should not be described as open source.

## Existing License Families To Consider

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

## Practical Recommendation For The Public Release

For the current release, the most conservative choice is to keep the
no-license/all-rights-reserved notice unless the project explicitly wants to
grant narrow rights to run experiments.

If narrow experimental rights are desired, use a clearly named
source-available research/evaluation license rather than an open-source license.
Do not call the project open source unless and until it uses an actual
open-source license.
