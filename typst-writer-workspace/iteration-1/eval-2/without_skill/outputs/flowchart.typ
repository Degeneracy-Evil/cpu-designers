#import "@preview/cetz:0.2.2"

#align(center)[
  #cetz.canvas({
    import cetz.draw: *

    // Define the nodes
    rect((-1.5, 0.5), (1.5, -0.5), name: "start")
    content("start", [Start])

    rect((-1.5, -2.0), (1.5, -3.0), name: "process")
    content("process", [Process])

    rect((-1.5, -4.5), (1.5, -5.5), name: "end")
    content("end", [End])

    // Draw the connections
    line("start.bottom", "process.top", mark: (end: ">"))
    line("process.bottom", "end.top", mark: (end: ">"))
  })
]