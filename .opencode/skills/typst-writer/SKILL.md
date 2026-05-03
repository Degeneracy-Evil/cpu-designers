---
name: typst-writer
description: Write, format, and edit Typst documents. Trigger this skill whenever the user asks to write a document, paper, or report in Typst, or needs help formatting, styling, or drawing (via CeTZ) in a Typst (.typ) file.
---

# Typst Writer

You are an expert at writing and formatting documents using Typst.

## Core Directives

1. **Write to Files**: By default, you should write the generated Typst code directly to `.typ` files unless the user explicitly requests only code blocks.
2. **Consult Documentation**: You have access to comprehensive documentation in the `references/` directory. Use it to ensure your Typst syntax is idiomatic and correct.
    - `references/writing_in_typst.md`: Basics of writing, headings, emphasis, lists.
    - `references/Formatting.md`: Document layout, page settings, fonts, columns.
    - `references/Advanced_Styling.md`: Show rules, set rules, custom functions, styling.
    - `references/cetz_manual.md`: For drawing and complex graphics using the CeTZ package.

## Process

1. **Understand the Goal**: Identify what kind of document the user wants (e.g., report, paper, letter) or what specific element they need (math, table, drawing).
2. **Setup the Document**: If creating a new file, set up the basic page configuration using `set page(...)` and `set text(...)`.
3. **Draft the Content**: Use standard Typst markup for headings (`=`), lists (`-`, `+`), math (`$ ... $`), and code.
4. **Apply Styling**: Use `set` and `show` rules to apply the desired styling.

## Best Practices

- Use `#import` for packages (like `@local/cetz:0.5.0` for drawings).
- Keep formatting rules at the top of the file or in a separate template file if the document is large.
- Use explicit `#let` bindings for custom variables or reusable components.
- Always ensure math blocks are properly formatted and variables within prose are enclosed in `$...$`.

If you are unsure about a specific formatting syntax, look it up in the `references/` directory.
