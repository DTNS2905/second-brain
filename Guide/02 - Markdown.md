---
tags:
  - guide
  - basics
---

# 02 - Markdown

Obsidian notes are plain **Markdown** files. Here is everything you need.

## Headings

```
# Heading 1
## Heading 2
### Heading 3
```

## Text Formatting

```
**bold**
*italic*
~~strikethrough~~
`inline code`
==highlight==
```

Renders as: **bold**, *italic*, ~~strikethrough~~, `inline code`, ==highlight==

## Lists

```
- Bullet item
- Another item
  - Nested item

1. First
2. Second
3. Third
```

## Checkboxes (Tasks)

```
- [ ] To do
- [x] Done
```

- [x] To do
- [ ] Done

## Code Blocks

````
```javascript
const greet = (name) => `Hello, ${name}`;
```
````

```javascript
const greet = (name) => `Hello, ${name}`;
```

## Blockquotes

```
> This is a quote
```

> This is a quote

## Tables

```
| Column 1 | Column 2 |
|----------|----------|
| Cell A   | Cell B   |
```

| Column 1 | Column 2 |
|----------|----------|
| Cell A   | Cell B   |

## Horizontal Rule

```
---
```

---

## Callouts (Obsidian-specific)

```
> [!note] Title
> Content inside the callout
```

> [!note] This is a note callout

> [!tip] This is a tip

> [!warning] This is a warning

> [!info] This is info

> [!danger] This is danger

## Images

```
![[image.png]]          ← embed a file from vault
![alt text](url)        ← external image
```

---

← [[01 - Interface]] | Next: [[03 - Linking]] →
