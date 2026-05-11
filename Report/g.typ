#import "@local/cetz:0.5.0"

#cetz.canvas({
  import cetz.draw: *
  set-style(content: (frame: "rect", stroke: none, fill: white, padding: .1))
  let w = 1.8
  let h = 1.0
  let dx = 3.5
  let y_top = 2.0
  let y_bot = 0

  rect((0, y_top), (w, y_top + h), name: "s0")
  content("s0", [#text(size: 11pt, "IDLE")])

  rect((dx, y_top), (dx + w, y_top + h), name: "s1")
  content("s1", [#text(size: 11pt, "FETCH")])

  rect((2 * dx, y_top), (2 * dx + w, y_top + h), name: "s2")
  content("s2", [#text(size: 11pt, "DECODE")])

  rect((3 * dx, y_top), (3 * dx + w, y_top + h), name: "s3")
  content("s3", [#text(size: 11pt, "EXEC")])

  rect((4 * dx, y_top), (4 * dx + w, y_top + h), name: "s4")
  content("s4", [#text(size: 11pt, "MEM")])

  rect((0, y_bot), (w, y_bot + h), name: "s7")
  content("s7", [#text(size: 11pt, "TRAP\nENTER")])

  rect((dx, y_bot), (dx + w, y_bot + h), name: "s8")
  content("s8", [#text(size: 11pt, "TRAP\nRET")])

  rect((2 * dx, y_bot), (2 * dx + w, y_bot + h), name: "s6")
  content("s6", [#text(size: 11pt, "CSR")])

  rect((4 * dx, y_bot), (4 * dx + w, y_bot + h), name: "s5")
  content("s5", [#text(size: 11pt, "WB")])

  line("s0.east", "s1.west", mark: (end: "straight"))
  line("s1.east", "s2.west", mark: (end: "straight"), name: "1t2")
  content((name: "1t2", anchor: 40%), anchor: "south", [#text(size: 10pt, "if_done")])
  line("s2.east", "s3.west", mark: (end: "straight"), name: "2t3")
  content((name: "2t3", anchor: 50%), anchor: "south", [#text(size: 10pt, "need_exe")])
  line("s3.east", "s4.west", mark: (end: "straight"), name: "3t4")
  content((name: "3t4", anchor: 50%), [#text(size: 10pt, "ld/st")])

  line("s2.south", "s7.north", bend: -25, mark: (end: "straight"), name: "2t7")
  content((name: "2t7", anchor: 75%), angle: ("2t7.start", 0%, "2t7.end"), [#text(size: 10pt, "trap")])
  line("s2.south", "s8.north", bend: -10, mark: (end: "straight"), name: "2t8")
  content((name: "2t8", anchor: 70%), angle: ("2t8.start", 0%, "2t8.end"), [#text(size: 10pt, "mret")])
  line("s2.south", "s6.north", mark: (end: "straight"), name: "2t6")
  content((name: "2t6", anchor: 50%), [#text(size: 10pt, "csr")])

  line("s3.south", "s5.north", bend: 15, mark: (end: "straight"), name: "3t5")
  content((name: "3t5", anchor: 50%), angle: ("3t5.start", 100%, "3t5.end"), [#text(size: 10pt, "R/I fast")])
  line("s4.south", "s5.north", mark: (end: "straight"), name: "4t5")
  content((name: "4t5", anchor: 50%), [#text(size: 10pt, "mem_done")])
  line("s6.east", "s5.west", mark: (end: "straight"))

  line("s5.north", "s1.south", bend: -15, mark: (end: "straight"), stroke: (dash: "dashed"), name: "5t1")
  content((name: "5t1", anchor: 30%), angle: ("5t1.start", 0%, "5t1.end"), [#text(size: 10pt, "next")])
  line("s7.north", "s1.south", mark: (end: "straight"), stroke: (dash: "dashed"))
  line("s8.north", "s1.south", mark: (end: "straight"), stroke: (dash: "dashed"))

  line(
    "s3.north",
    (rel: (0, 0.5), to: "s3.north"),
    (rel: (0, 0.5), to: "s1.north"),
    "s1.north",
    mark: (end: "straight"),
    name: "3t1",
  )
  content((name: "3t1", anchor: 50%), [#text(size: 10pt, "branch")])

  line("s3.south", (11.4, -0.5), (0.9, -0.5), "s7.south", mark: (end: "straight"), name: "3t7")
  content((name: "3t7", anchor: 50%), [#text(size: 10pt, "br+trap")])

  line("s5.south", (14.9, -0.3), (0.9, -0.3), "s7.south", mark: (end: "straight"), name: "5t7")
  content((name: "5t7", anchor: 50%), [#text(size: 10pt, "trap")])

  line("s2.north", "s1.north", bend: -30, mark: (end: "straight"), name: "2t1f")
  content((name: "2t1f", anchor: 50%), [#text(size: 10pt, "fence")])
})

#align(center)[#cetz.canvas({
  import cetz.draw: *

  rect((0, 2), (3, 3), name: "bridge")
  content("bridge", [#text(size: 10pt, "cpu_bus_bridge")])

  rect((5, 0), (10, 5), name: "bus")
  content("bus.north", anchor: "south", [#text(size: 10pt, "ahb_lite_bus")])

  rect((5.5, 3.5), (9.5, 4.5), name: "decoder")
  content("decoder", [#text(size: 10pt, "ahb_decoder")])

  rect((5.5, 1), (7.0, 2.5), name: "sram")
  content("sram", [#text(size: 10pt, "ahb_sram")])

  rect((7.5, 1), (9.5, 2.5), name: "apbb")
  content("apbb", [#text(size: 10pt, "AHB→APB")])

  line("bridge.east", "bus.west", mark: (end: "straight"), name: "l1")
  content("l1", anchor: "south", padding: .1, [#text(size: 10pt, "AHB-Lite")])
  line("decoder.south", "sram.north", stroke: (dash: "dashed"), mark: (end: "straight"), name: "bus_sram")
  line("decoder.south", "apbb.north", stroke: (dash: "dashed"), mark: (end: "straight"), name: "bus_apb")

  content((name: "bus_sram", anchor: 50%), anchor: "west", [#text(size: 10pt, "HSEL0")])
  content((name: "bus_apb", anchor: 50%), anchor: "east", [#text(size: 10pt, "HSEL1")])
})]

#align(center)[#cetz.canvas({
  import cetz.draw: *

  rect((0, 1), (2.5, 2), name: "bridge")
  content("bridge", [#text(size: 10pt, "AHB→APB")])

  rect((4, 0), (10.5, 3), name: "apb")
  content("apb.north", anchor: "south", [#text(size: 10pt, "APB总线")])

  rect((4.3, 0.3), (5.7, 1.5), name: "gpio")
  content("gpio", [#text(size: 10pt, "GPIO")])

  rect((6.0, 0.3), (7.4, 1.5), name: "timer")
  content("timer", [#text(size: 10pt, "Timer")])

  rect((7.7, 0.3), (9.1, 1.5), name: "uart")
  content("uart", [#text(size: 10pt, "UART")])

  rect((9.4, 0.3), (10.3, 1.5), name: "spi")
  content("spi", [#text(size: 10pt, "SPI")])

  line("bridge.east", "apb.west", mark: (end: "straight"), name: "l1")
  content("l1", anchor: "south", padding: .1, [#text(size: 10pt, "APB")])

  content((5.0, 1.8), [#text(size: 10pt, "00")])
  content((6.7, 1.8), [#text(size: 10pt, "01")])
  content((8.4, 1.8), [#text(size: 10pt, "10")])
  content((9.85, 1.8), [#text(size: 10pt, "11")])
})]

#align(center)[#cetz.canvas({
  import cetz.draw: *

  let box_w = 1.8
  let box_h = 1.0
  let gap_x = 1.2
  let gap_y = 1.2

  let stages = (
    ("fetch", "Fetch"),
    ("decode", "Decode"),
    ("execute", "Execute"),
    ("mem", "Memory"),
    ("wb", "Writeback"),
  )
  for (i, s) in stages.enumerate() {
    let (id, label) = s
    let x_pos = i * (box_w + gap_x)
    rect((x_pos, 0), (x_pos + box_w, box_h), name: id)
    content(id, [#text(size: 10pt, label)])
  }

  rect((rel: (-1.0, -1.5), to: "execute"), (rel: (1.0, -2.5), to: "execute"), fill: gray, name: "regfile")
  content("regfile", [#text(size: 10pt, "RegFile")])

  rect((rel: (-1.25, -1.5), to: "fetch"), (rel: (1.25, -2.5), to: "fetch"), fill: gray, name: "icache")
  content("icache", [#text(size: 10pt, "iCache")])

  rect((rel: (-1.25, -1.5), to: "mem"), (rel: (1.25, -2.5), to: "mem"), fill: gray, name: "dcache")
  content("dcache", [#text(size: 10pt, "dCache")])

  rect((rel: (-1.25, 1.5), to: "fetch"), (rel: (1.25, 2.5), to: "fetch"), name: "ctrl")
  content("ctrl", [#text(size: 10pt, "Controller")])

  rect(
    (rel: (-4, -1.5), to: "icache"),
    (rel: (-1.5, -2.5), to: "icache"),
    fill: gray,
    name: "ahb",
  )
  content("ahb", [#text(size: 10pt, "AHB-Lite")])

  rect((rel: (-4, -1.5), to: "ahb"), (rel: (-1.5, -2.5), to: "ahb"), fill: gray, name: "apb")
  content("apb", [#text(size: 10pt, "APB+Perips")])

  rect((rel: (-1.0, 1.5), to: "mem"), (rel: (1.0, 2.5), to: "mem"), fill: gray, name: "csr")
  content("csr", [#text(size: 10pt, "Trap/CSR")])

  line("fetch.east", "decode.west", mark: (end: "straight"), name: "lfd")
  content("lfd", anchor: "south", padding: .1, text(size: 10pt, "96bit"))
  line("decode.east", "execute.west", mark: (end: "straight"), name: "lde")
  content("lde", anchor: "south", padding: .1, text(size: 10pt, "320bit"))
  line("execute.east", "mem.west", mark: (end: "straight"), name: "lem")
  content("lem", anchor: "south", padding: .1, text(size: 10pt, "207bit"))
  line("mem.east", "wb.west", mark: (end: "straight"), name: "lmw")
  content("lmw", anchor: "south", padding: .1, text(size: 10pt, "168bit"))

  line("icache.north", "fetch.south", mark: (end: "straight"))
  line("dcache.north", "mem.south", mark: (symbol: "straight"), bend: -20)
  line("ahb", "icache", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ahb", "dcache", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("apb", "ahb", mark: (end: "straight"))

  line("ctrl.south", "fetch", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "decode.north", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "execute.north", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "mem.north", stroke: (dash: "dashed"), mark: (end: "straight"))
  line("ctrl.south", "wb.north", stroke: (dash: "dashed"), mark: (end: "straight"))

  line("regfile.west", "decode.south", mark: (end: "straight"))
  line("wb.south", "regfile.north", mark: (end: "straight"))

  line("csr.south", "mem.north", mark: (end: "straight"))
  line("csr.west", "execute.north", stroke: (dash: "dashed"), mark: (end: "straight"))
})]
