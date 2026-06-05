# Discussion: Feedback on the BLIMP Progress Tracker Design

* **Date**: 2026-06-06
* **Author**: Antigravity (<antigravity@google.com>)
* **Topic**: Rationale, limitations, and future improvements for the filesystem-based ticket tracker (`docs/progress/`).

---

Following a review of [agents/progress-tracker-design.md](../progress-tracker-design.md) and [docs/progress/README.md](../../docs/progress/README.md), the system is extremely robust for multi-agent workflows. To address some of the identified limitations, we propose the following improvements:

## 1. Board Validation Mode (`tools/progress.sh check`)
As noted in the design document, slug typos and circular dependencies are currently hard to debug and fail silently.
* **Proposal**: Add a validation/linter command to [tools/progress.sh](../../tools/progress.sh) (e.g., `./tools/progress.sh check` or `./tools/progress.sh lint`).
* **Checks**:
  1. Verify that all slugs referenced in `Blocked-by:` lines actually exist as files on the board (preventing silent blockage due to typos).
  2. Run a Depth-First Search (DFS) cycle-detection algorithm to ensure the dependency graph remains a Directed Acyclic Graph (DAG).
  3. Validate that tickets in `working/` have an `Owner:` set and tickets in `done/` have a commit logged.
* **Integration**: Once implemented, we can add this check to the `Makefile` (e.g., under `make test` or `make fpc-check`) so that any invalid board state automatically fails the local build verification.

## 2. Transition CLI Helpers
Manual file moves via `git mv` combined with manual edits to update the `Status:` and `Owner:` fields can be tedious and error-prone.
* **Proposal**: Add transition helpers to [tools/progress.sh](../../tools/progress.sh):
  * `./tools/progress.sh claim <slug>`: Moves the ticket to `working/`, automatically updates the `Status:` header to `working`, and prompts for or infers the `Owner`.
  * `./tools/progress.sh resolve <slug> <commit-hash>`: Moves the ticket to `done/`, updates the status, and appends the resolution log entry.

## 3. On-Demand Visual Kanban Board (`BOARD.md`)
While keeping a static, manually-updated board summary in git leads to drift and merge conflicts, having a unified visual view of the board is highly beneficial.
* **Proposal**: Add a command `./tools/progress.sh board-md` that parses all the status directories and outputs a clean markdown table representing a Kanban-like grid.
* **Workflow**: Add `docs/progress/BOARD.md` to [.gitignore](../../.gitignore) so it is never checked in, but remains easily generated locally on-demand for human/agent review.
