# CLAUDE.md (global)

Personal preferences that apply across all projects. Project-level CLAUDE.md files take precedence for anything specific to that repo.

## Context
- Primary machine: `sutala`, a NixOS host that's both home server and desktop (niri compositor). Main repo: `nix-configs` (NixOS + nix-darwin, hosts `sutala` and `mac-work`).
- GitHub user: kra3.

## Verification
Before asserting file or config state, re-read it and reference the verification. If you can't verify, say so explicitly rather than assuming.

## Git & commits
- Short, imperative commit messages scoped to one logical change.
- Create new commits rather than amending; never force-push or skip hooks unless explicitly asked.
- Commits are GPG-signed (`commit.gpgsign`). If GPG is unavailable (user away from the keyboard), commit unsigned, but re-sign (amending unpushed commits is fine for this) before pushing; never push an unsigned commit.
- Check `git status`/`diff` before staging broad changes, and check file contents (not just filenames) for secrets before committing.

## Working style
- Ask before destructive or hard-to-reverse actions, even when technically permitted by tool permissions — this applies especially on `sutala` since sessions often run directly on it, not just against a checkout.
- Prefer editing existing files over creating new ones; no unrequested abstractions, refactors, or cleanup alongside a focused task.
- Turn a task into a verifiable goal (a test or command that proves it), and loop until that check passes.

## Conventions
- Don't override upstream defaults (e.g. LazyVim keymaps) unasked.
- Check `gh pr view` / `gh pr checks` live before reporting PR or CI state.
- Pasteable shell must be zsh-safe: quote `#`, `*`, `?`.

## Skills at each step
Invoke the matching skill at each step, on top of any domain skill:
- Designing new behaviour: superpowers:brainstorming, then ponytail:ponytail while building.
- A bug or unexpected behaviour: superpowers:systematic-debugging.
- Before pushing or opening a PR: ponytail:ponytail-review, then code-review. Touch the review-gate marker only after these and verification ran.
- Review findings received: superpowers:receiving-code-review.
- Before claiming done, fixed or passing: superpowers:verification-before-completion.

Escape latch: a change under ~20 lines that touches nothing high-impact skips brainstorming and the reviews, never verification. High-impact is judged by effect (security, access, secrets, data loss, deploy, anything hard to undo), not only by the review-gate hook's path list; only the user may set `CLAUDE_SKIP_REVIEW_GATE=1`.

## Code comments
- Keep comments to one line by default. Never narrate the decision process, alternatives considered, or tradeoffs weighed — that belongs in the commit message or PR description, not the file.
- Only comment a genuinely non-obvious constraint or gotcha; if removing the comment wouldn't confuse a future reader, don't write it. Before finishing any change, re-scan added comments and cut anything that restates the diff in prose or reads like a note to self.

@RTK.md
