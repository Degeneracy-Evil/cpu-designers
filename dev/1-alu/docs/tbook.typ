#let tbook(title_in, doc) = {
  set title(title_in)
  set page(header: align(right, [_技术文档 - #title_in _]))
  set text(size: 18pt)
  show heading: it => {
    block([#sym.section *#it.body*], below: 1em)
  }
  set par(first-line-indent: (amount: 2em, all: true))
  show strong: text.with(font: "Microsoft YaHei")
  show emph: text.with(font: ("Calibri", "LiSu"))
  doc
}