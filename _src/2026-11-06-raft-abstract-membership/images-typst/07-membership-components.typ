#import "style.typ": *

#diagram(
  1060,
  650,
  "07. Membership combines quorum rules and node information",
  "Both parts travel together in each config log entry.",
  {
    card((420, -130), 220, 60, fill: panel-fill, stroke: pen(panel-line, 1.5))[
      #head[Membership]
    ]
    line((530, -190), (530, -225), stroke: pen(slate, 1.5))
    line((280, -225), (790, -225), stroke: pen(slate, 1.5))
    line((280, -225), (280, -260), stroke: pen(slate, 1.5))
    line((790, -225), (790, -260), stroke: pen(slate, 1.5))

    panel((40, -260), 480, 330)
    panel((560, -260), 460, 330)
    content((280, -300), head[quorum rules], anchor: "base")
    content((790, -300), head[nodes], anchor: "base")

    content((70, -330), small[weights], anchor: "base-west")
    card((65, -345), 430, 105, fill: white, stroke: pen(panel-line, 1.5))
    for (index, weight) in (2, 1, 1, 1).enumerate() {
      let x = 105 + index * 115
      node((x, -380), str(index + 1), r: 18)
      content((x, -425), tiny("weight " + str(weight)), anchor: "base")
    }
    quorum((65, -475), 195, 80)[
      #align(center)[#small(fill: read-text)[read quorum] \ #mono(fill: read-text)[weight >= 3]]
    ]
    quorum((285, -475), 195, 80, kind: "write")[
      #align(center)[#small(fill: write-text)[write quorum] \ #mono(fill: write-text)[weight >= 3]]
    ]

    content((790, -330), tiny[Campaigner | ReceiveLogs], anchor: "base")
    for id in range(1, 5) {
      let y = 365 + (id - 1) * 60
      node((605, -y), str(id), r: 18)
      line((623, -y), (650, -y), stroke: pen(slate, 1.5))
      content((670, -(y + 6)), mono("127.0.0.1:" + str(37000 + id)), anchor: "base-west")
    }
  },
)
