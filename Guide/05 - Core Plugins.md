---
tags:
  - guide
  - intermediate
---

# 05 - Core Plugins

Core plugins come built into Obsidian. Enable them at:
**Settings → Core Plugins**

---

## Daily Notes

Creates one note per day automatically.

**Setup:**
1. Settings → Core Plugins → Daily Notes → Enable
2. Set folder: `Daily`
3. Set date format: `YYYY-MM-DD`
4. Optionally set a template (see Templates below)

**Usage:**
- Press `Cmd+P` → type "Daily note" → opens today's note
- Or click the calendar icon in the left sidebar

**Example daily note:**
```markdown
# 2026-06-03

## Today's focus
- 

## Notes


## Done
- 
```

---

## Templates

Reusable note skeletons. Stop rewriting the same structure.

**Setup:**
1. Settings → Core Plugins → Templates → Enable
2. Set template folder: `Templates`

**Create a template:**
Make a note in your `Templates/` folder.

Use these special variables:
```
{{title}}    ← inserts the note's title
{{date}}     ← inserts today's date (YYYY-MM-DD)
{{time}}     ← inserts current time
```

**Usage:**
Open any note → `Cmd+P` → "Insert template" → choose your template

> See the ready-made templates in [[Templates/Daily Note]] and [[Templates/General Note]]

---

## Canvas

A free-form visual workspace. Drag notes, images, and cards onto an infinite board.

**Create one:** `Cmd+P` → "New canvas"

Best for:
- Brainstorming / mind maps
- Planning project structure
- Visualizing relationships between ideas

---

## Graph View

`Cmd+G` — visual map of all your notes and their links.

**Tips:**
- Use filters to show only tagged notes (e.g. `tag:#project`)
- Increase node size to see heavily-linked notes
- Color groups by tag or folder in Graph settings

---

## Backlinks

Right sidebar → backlink icon.
Shows every note that links to the current one — builds connections passively.

---

## Quick Switcher

`Cmd+O` — fastest way to open any note by name.
Type a few letters — fuzzy search finds it instantly.

---

## Search

`Cmd+Shift+F` — full-text search across the entire vault.

Advanced search operators:
```
tag:#book              ← notes with this tag
path:Projects          ← notes in this folder
file:2026              ← notes with this in the filename
"exact phrase"         ← exact match
```

---

← [[04 - Organization]] | Next: [[06 - Bases]] →
