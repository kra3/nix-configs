---
name: ui-workflow
description: Use when building or restyling UI (page, component, screen) and the user wants the full design pass. Runs design system, build, audit, polish in order, loading each upstream skill on demand without installing it.
---

# UI workflow

Run steps in order. Skip a step only if the user says so. Load each upstream skill by reading its `SKILL.md` for this task only; never install plugins.

## Sources

| Step | Skill | Where to read it |
|---|---|---|
| 1 | ui-ux-pro-max | GitHub `nextlevelbuilder/ui-ux-pro-max-skill`, find its `SKILL.md` |
| 2 | frontend-design | `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/frontend-design/skills/frontend-design/SKILL.md` |
| 3 | web-design-guidelines | GitHub `vercel-labs/agent-skills`, `skills/web-design-guidelines/SKILL.md` |
| 4 | impeccable | GitHub `pbakaus/impeccable`, find its `SKILL.md` |

For GitHub sources use `gh api repos/<owner>/<repo>/contents/<path>` or `gh search code --repo <owner>/<repo> filename:SKILL.md`. If a source is missing or its path has moved, say so and skip that step; don't guess its contents.

## Steps

1. **Design system** (ui-ux-pro-max): choose style, palette, type scale, spacing. Skip if the project already has a design system; reuse it instead.
2. **Build** (frontend-design): write the UI using the step 1 decisions.
3. **Audit** (web-design-guidelines): review the code from step 2 against the rules. List violations as `file:line: rule`.
4. **Polish** (impeccable): fix the step 3 findings, then refine details (spacing, motion, states). Re-run step 3 on the changed files.

## Done when

- Step 3 audit on the final code reports no open violations.
- The user has seen the result in a browser or screenshot, not only the code.

## Skip rules

- Small tweak: steps 2 and 3 only.
- Existing screen to fix: run step 3 first, then step 2 to apply fixes.
