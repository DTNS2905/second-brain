---
tags:
  - guide
  - advanced
---

# 06 - Bases

Bases turns your notes into a **database** — without leaving Markdown.
A `.base` file queries note properties and displays them as a table, card, or list.

---

## How It Works

```
Note frontmatter  →  .base file queries it  →  Table / Card view
```

Any property you add in a note's frontmatter becomes queryable.

---

## Create a Base

**Option A — from the app:**
`Cmd+P` → "Create new base" → Obsidian generates a `.base` file

**Option B — manually:**
Create a file with the `.base` extension and write YAML inside.

---

## .base File Syntax (YAML)

```yaml
filters:
  and:
    - file.hasTag("book")

properties:
  file.name:
    displayName: Title
  status:
    displayName: Status
  rating:
    displayName: Rating

views:
  - type: table
    name: All Books
    order:
      - note.status
```

---

## Filters

```yaml
# Single tag filter
filters:
  and:
    - file.hasTag("book")

# Multiple conditions
filters:
  and:
    - file.hasTag("project")
    - 'status = "active"'

# OR logic
filters:
  or:
    - file.hasTag("book")
    - file.hasTag("article")
```

---

## View Types

| Type | Description |
|------|-------------|
| `table` | Spreadsheet rows — best for lists |
| `card` | Card grid — best for visual browsing |
| `list` | Simple file list |

---

## Multiple Views in One Base

```yaml
views:
  - type: table
    name: All
    order:
      - note.status

  - type: table
    name: Done
    filters:
      and:
        - 'status = "done"'

  - type: card
    name: Cards
```

Each view appears as a **tab** at the top of the base.

---

## Formula Properties

Computed values based on other properties:

```yaml
formulas:
  is_overdue: 'if(due < today(), "overdue", "ok")'

properties:
  formula.is_overdue:
    displayName: Overdue?
```

---

## Real Example — Reading List

**Notes** (each book is a `.md` file with this frontmatter):
```yaml
---
tags: [book]
author: Robert C. Martin
status: done
rating: 5
---
```

**Reading List.base:**
```yaml
filters:
  and:
    - file.hasTag("book")

properties:
  file.name:
    displayName: Title
  author:
    displayName: Author
  status:
    displayName: Status
  rating:
    displayName: Rating

views:
  - type: table
    name: All Books
  - type: table
    name: Done
    filters:
      and:
        - 'status = "done"'
```

---

← [[05 - Core Plugins]] | Next: [[07 - Advanced]] →
