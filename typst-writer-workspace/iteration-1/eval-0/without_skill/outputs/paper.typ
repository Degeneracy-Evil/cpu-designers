#let project(title: "", authors: (), abstract: none, body) = {
  set document(author: authors, title: title)
  set page(paper: "us-letter", numbering: "1")
  set text(font: "New Computer Modern", size: 10pt)

  align(center)[
    #block(text(weight: 700, 1.75em, title))
  ]

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

  if abstract != none [
    #align(center)[
      #heading(
        outlined: false,
        numbering: none,
        text(0.85em, smallcaps[Abstract]),
      )
    ]
    #pad(x: 2em)[#abstract]
  ]

  show: columns.with(2)
  set par(justify: true)

  body
}

#show: project.with(
  title: "A Simple Academic Paper Template in Typst",
  authors: (
    "Jane Doe",
    "John Smith",
  ),
  abstract: [
    This document provides a basic template for academic papers using Typst. 
    It includes essential elements such as a title, author list, abstract, and a two-column layout. 
    Placeholder text is used to demonstrate the appearance of the document structure.
  ],
)

= Introduction
#lorem(150)

= Related Work
#lorem(200)

= Methodology
#lorem(250)

= Results
#lorem(200)

= Conclusion
#lorem(100)
