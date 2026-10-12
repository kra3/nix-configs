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
- Check `git status`/`diff` before staging broad changes, and check file contents (not just filenames) for secrets before committing.

## Working style
- Ask before destructive or hard-to-reverse actions, even when technically permitted by tool permissions — this applies especially on `sutala` since sessions often run directly on it, not just against a checkout.
- Prefer editing existing files over creating new ones; no unrequested abstractions, refactors, or cleanup alongside a focused task.

## Code comments
- Keep comments to one line by default. Never narrate the decision process, alternatives considered, or tradeoffs weighed — that belongs in the commit message or PR description, not the file.
- Only comment a genuinely non-obvious constraint or gotcha; if removing the comment wouldn't confuse a future reader, don't write it. Before finishing any change, re-scan added comments and cut anything that restates the diff in prose or reads like a note to self.

@RTK.md
