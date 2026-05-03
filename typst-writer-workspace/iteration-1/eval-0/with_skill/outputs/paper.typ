#let project(title: "", authors: (), abstract: none, body) = {
  // Set document metadata.
  set document(title: title, author: authors)

  // Set the body font.
  set text(font: "Linux Libertine", size: 11pt)

  // Title.
  align(center)[
    #block(text(weight: 700, 1.75em, title))
  ]

  // Authors.
  pad(
    top: 0.5em,
    bottom: 0.5em,
    x: 2em,
    grid(
      columns: (1fr,) * calc.min(3, authors.len()),
      gutter: 1em,
      ..authors.map(author => align(center, strong(author))),
    ),
  )

  // Abstract.
  if abstract != none {
    pad(
      x: 2em,
      top: 1em,
      bottom: 1em,
      align(center)[
        #heading(
          outlined: false,
          numbering: none,
          text(0.85em, smallcaps[Abstract]),
        )
        #abstract
      ],
    )
  }

  // Two column layout.
  show: columns.with(2, gutter: 1.3em)

  // Body text.
  body
}

#show: project.with(
  title: "A Simple Academic Paper Template in Typst",
  authors: (
    "Alice Smith",
    "Bob Jones",
  ),
  abstract: [
    This is the abstract of the paper. It summarizes the contents of the paper.
    Typst is a new markup-based typesetting system that is designed to be as
    powerful as LaTeX while being much easier to learn and use.
  ],
)

= Introduction

This is the introduction. Here is some placeholder text for the two column layout.
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

== Background

Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.

= Methodology

We used Typst to format this document. It is very fast and has a simple syntax.
Here is some more placeholder text to fill out the columns and show the two column
layout in action.

= Conclusion

Typst is a great tool for writing academic papers.