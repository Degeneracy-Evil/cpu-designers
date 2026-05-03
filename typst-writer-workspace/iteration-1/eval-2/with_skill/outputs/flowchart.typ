#import "@preview/cetz:0.2.2"

#align(center)[
  #cetz.canvas({
    import cetz.draw: *

    content((0, 0), [Start], frame: "rect", name: "start", padding: 0.2)
    content((0, -2), [Process], frame: "rect", name: "process", padding: 0.2)
    content((0, -4), [End], frame: "rect", name: "end", padding: 0.2)

    line("start", "process", mark: (end: ">"))
    line("process", "end", mark: (end: ">"))
  })
]
