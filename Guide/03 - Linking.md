---
tags:
  - guide
  - basics
---

# 03 - Linking

Linking is what makes Obsidian more than just a text editor.
It turns isolated notes into a **connected knowledge graph**.

## Internal Links (Wikilinks)

```
[[Note Name]]
```

- Type `[[` and Obsidian shows an autocomplete list of your notes
- If the note doesn't exist yet, Obsidian creates it when you click the link
- Links are **bidirectional** — Obsidian tracks both directions automatically

## Link with Custom Text

```
[[Note Name|Display Text]]
```

Example: [[03 - Linking|this note]] ← shows "this note" but links here

## Link to a Heading

```
[[Note Name#Heading]]
```

Example: `[[02 - Markdown#Tables]]` jumps straight to the Tables section

## Link to a Block

```
[[Note Name#^blockid]]
```

Add `^myid` at the end of any paragraph, then link to it with `#^myid`.

## Embed a Note

```
![[Note Name]]
```

This renders the full content of another note inline — like a transclusion.

## External Links

```
[Display Text](https://url.com)
```

## Backlinks

When you open any note, the **right sidebar** shows every other note that links to it.
This is the backlinks panel — it builds your knowledge graph automatically.

Open the right sidebar → click the backlink icon to see it.

## Graph View

Press `Cmd+G` to open the Graph View.

```
   [03 - Linking] ──── [01 - Interface]
          │
          └──────────── [02 - Markdown]
                │
                └─────── [START HERE]
```

Each dot is a note. Lines are links. The more links, the more central a note becomes.

---

← [[02 - Markdown]] | Next: [[04 - Organization]] →
