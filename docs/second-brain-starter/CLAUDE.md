# Vault rules for Claude

Arun's second brain. Two layers:
- an **action layer**: PARA folders plus GTD-style capture, clarify and weekly review;
- a **knowledge layer**: Zettelkasten-style evergreen notes and the maps that link them.

The vault is a git repo that the Mac and sutala sync every few minutes; never commit yourself.
Claude reaches it through Claude Code: on the Mac in the clone, or on sutala in `~/second-brain`
(the `second-brain` MCP tools), which the phone drives through Remote Control.

## Folders and what goes where
| Folder | Holds | Rule |
| --- | --- | --- |
| `0 Inbox` | Fleeting captures | The only place raw input lands. Never leave anything here after a weekly review |
| `1 Projects` | One note per project with an end. Tasks as `- [ ]` inside it | Every active project has at least one open task: its next action |
| `2 Areas` | Ongoing responsibilities (Health, Home, Career, Finances); recurring tasks | No end date; review monthly |
| `3 Sources` | One literature note per book, article, video or course module | Summary in Arun's words; **bold** = key passage, ==highlight== = best of the bold |
| `4 Notes` | Evergreen notes: one idea each, title is a claim | Flat, no subfolders. **Arun writes these, not Claude** (see below) |
| `5 Maps` | Structure notes linking related evergreen notes on a topic | Create one when a topic reaches about 7 notes |
| `6 Archive` | Finished projects, dropped areas, used-up sources | Evergreen notes and maps are never archived |
| `Templates` | Note templates | Never file notes here |

## Note conventions
- Frontmatter on every note: `created` (ISO date) and `type` (one of `capture`, `project`, `area`,
  `source`, `evergreen`, `map`). Projects add `status: active | waiting | someday | done`.
- Evergreen titles are full claims in sentence case:
  "Least privilege limits damage from compromised accounts", not "Least privilege".
- Link with `[[Note title]]`. Every evergreen note links to at least one other note and to its sources.
- Tasks: `- [ ] verb-first action` in project or area notes; waiting on someone: `- [ ] waiting: …`.
- Tags only for cross-cutting status: `#idea`, `#question`, `#decision`, `#person`. Topics belong in links and maps, not tags.

## The evergreen rule
Writing evergreen notes in his own words is how Arun learns, so in `4 Notes`:
- **Do**: point out candidate ideas ("this source has 3 note-worthy claims"), find related notes,
  propose links, flag duplicates and orphans, and ask questions that sharpen a claim.
- **Don't**: write or rewrite an evergreen note's body, unless Arun dictates the words
  ("save this note: …") or asks explicitly. Adding links he approved is fine.

## Workflows

### Capture (anytime)
Save as-is to `0 Inbox/YYYY-MM-DD HHMM <short title>.md` with the Capture template. Don't polish dictation.

### Weekly review (when Arun says "weekly review")
Go through it in order. Propose, wait for a yes or a change, then act.
1. **Clarify the inbox.** For each capture, propose exactly one of:
   - a task in an existing project or area;
   - a new project note, with a first next action;
   - a source stub in `3 Sources`;
   - a candidate evergreen idea (list it; Arun writes it);
   - delete.

   Batch the obvious ones and ask about the ambiguous ones. The inbox ends at zero.
2. **Projects.** List active projects with their open tasks. Flag any project with no open task or no
   edit in 14 days, and every `waiting:` item. Ask which tasks are this week's next actions. Offer to
   archive finished projects.
3. **Knowledge.** Show:
   - this week's new and changed sources and notes;
   - orphan evergreen notes (no backlinks), with link suggestions;
   - candidate ideas still unwritten;
   - topics with about 7 or more notes and no map.
4. **Summary.** Close with three lines: what moved, what's next, what's stalled.

### Studying a source
On "new source: …", create the source note from the Source template. If asked, draft a summary into
its Summary section, clearly separate from Arun's own notes. Afterwards, list candidate claims for
evergreen notes.

### Express
On "gather my notes on X", collect the relevant maps, evergreen notes and sources as a linked outline
in the project that needs them. Draft from those notes only when asked, and cite them with `[[links]]`.

## Never
- Delete notes: archive them instead (move to `6 Archive`).
- Touch `.obsidian/`, `.trash/`, `.git*`.
- Change the meaning of Arun's words when tidying.
