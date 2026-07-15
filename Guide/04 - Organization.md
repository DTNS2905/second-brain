---
tags:
  - guide
  - intermediate
---

# 04 - Organization

Three tools for organizing your vault: **Folders**, **Tags**, and **Properties**.

---

## Folders

Use folders sparingly. Over-organizing early is a common mistake.

**Good folder structure:**
```
Vault/
├── Daily/          ← daily notes
├── Projects/       ← active work
├── Resources/      ← reference material
├── Archive/        ← finished or old notes
└── Templates/      ← reusable note templates
```

> [!tip] Rule of thumb
> Create a folder only when you have 5+ notes that clearly belong together.
> Links matter more than folders.

---

## Tags

Tags are added with `#` anywhere in a note or in frontmatter.

```markdown
This note is about #javascript and #learning
```

Or in frontmatter:
```yaml
tags:
  - javascript
  - learning
```

**Tags vs Folders:**

| | Folders | Tags |
|--|---------|------|
| A note can be in | 1 folder | many tags |
| Best for | broad structure | cross-cutting topics |
| Visible in sidebar | yes | yes (Tag Pane) |

---

## Properties (Frontmatter)

Properties are key-value pairs at the top of a note, written in YAML.
Obsidian renders them as a clean panel when you click the properties area.

```yaml
---
title: My Note
date: 2026-06-03
status: active
tags:
  - project
priority: high
---
```

**Common property types:**

| Type | Example |
|------|---------|
| Text | `status: active` |
| Number | `rating: 4` |
| Date | `due: 2026-06-10` |
| Checkbox | `done: false` |
| List | `tags: [a, b, c]` |

> [!info] Why properties matter
> Properties are what power [[06 - Bases]].
> Any property you add here can be queried, filtered, and displayed as a table.

---

## Combining All Three

```
Resources/
└── Clean Code.md
    ---
    type: book        ← property (queryable)
    status: done      ← property
    tags:             ← tag (searchable)
      - book
      - programming
    ---
```

- **Folder** → physical location (`Resources/`)
- **Tag** → topic category (`#book`, `#programming`)
- **Property** → structured data (`status: done`, `rating: 5`)

---

← [[03 - Linking]] | Next: [[05 - Core Plugins]] →
