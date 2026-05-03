#import "@local/cetz:0.5.0"
#align(center)[#cetz.canvas({
  import cetz.draw: *

  let sw = 4.0
  let sh = 1.3
  let dx = 5.6
  let dy = -2.8

  rect((0, 0), (sw, sh), name: "idle")
  content("idle", [#text(size: 9pt, "IDLE")])

  rect((dx, 0), (dx + sw, sh), name: "read")
  content("read", [#text(size: 9pt, "READ")])

  rect((2 * dx, 0), (2 * dx + sw, sh), name: "read2")
  content("read2", [#text(size: 9pt, "READ2")])

  rect((0, dy), (sw, dy + sh), name: "wmod")
  content("wmod", [#text(size: 9pt, "W_MODIFY")])

  rect((dx, dy), (dx + sw, dy + sh), name: "wmod2")
  content("wmod2", [#text(size: 9pt, "W_MODIFY2")])

  rect((2 * dx + 0.25, dy), (2 * dx + sw, dy + sh), name: "wcommit")
  content("wcommit", [#text(size: 9pt, "W_COMMIT")])

  line("idle", "read", mark: (end: "straight"), name: "l1")
  content("l1", anchor: "south", padding: .1, [#text(size: 10pt, "is_load")])

  line("idle", "wmod", mark: (end: "straight"), name: "l2")
  content("l2", anchor: "east", padding: .1, [#text(size: 10pt, "is_store")])

  line("read", "read2", mark: (end: "straight"), name: "l3")
  content("l3", anchor: "south", padding: .1, [#text(size: 10pt, "1 cycle")])

  line("read2", (rel: (0, 1.8), to: "read2"), (rel: (0, 1.8), to: "idle"), "idle", mark: (end: "straight"), name: "l4")
  content("l4", anchor: "south", padding: .0, [#text(size: 10pt, "sample→done")])

  line("wmod", "wmod2", mark: (end: "straight"), name: "l5")
  content("l5", anchor: "south", padding: .1, [#text(size: 10pt, "1 cycle")])

  line("wmod2", "wcommit", mark: (end: "straight"), name: "l6")
  content("l6", anchor: "south", padding: .1, [#text(size: 10pt, "merge→we")])

  line(
    "wcommit",
    (rel: (0, +1.2), to: "wcommit"),
    (rel: (1, -1), to: "idle"),
    "idle",
    mark: (end: "straight"),
    name: "l7",
  )
  content("l7", anchor: "east", padding: .0, [#text(size: 10pt, "done")])

  line(
    (rel: (-0.8, 0), to: "idle.north"),
    (rel: (-0.8, 1.5), to: "idle.north"),
    (rel: (0.8, 1.5), to: "read2.north"),
    (rel: (0.8, 0), to: "read2.north"),
    mark: (end: "straight"),
    stroke: (dash: "dashed"),
    name: "lb1",
  )
  content("lb1", anchor: "south", padding: .1, [#text(size: 10pt, "!is_load&&!is_store→done")])

  line(
    (rel: (0, -0.3), to: "idle.east"),
    (rel: (0, 0.3), to: "wmod2.west"),
    mark: (end: "straight"),
    stroke: (dash: "dashed"),
    name: "lb2",
  )
  content("lb2", anchor: "north", padding: .1, [#text(size: 10pt, "misalign→done")])
})]
