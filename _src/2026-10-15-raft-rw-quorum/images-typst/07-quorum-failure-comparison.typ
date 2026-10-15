#import "style.typ": *

#let node-radius = 22

#let failed-node(pos, label) = {
  circle(pos, radius: node-radius, fill: bad-fill, stroke: pen(bad-ink, 2))
  content(pos, text(size: 23 * px, weight: "bold", fill: bad-text, label))
  let marker = (pos.at(0) + 28, pos.at(1) - 28)
  cross(marker, size: 14)
}

#diagram(
  960,
  700,
  "07. Three diagonal failures stop the grid quorums",
  "Nodes 1, 5 and 9 fail. Both configurations have the same six survivors.",
  {
    panel((40, -110), 420, 430)
    panel((500, -110), 420, 430)
    content((250, -150), head[Grid: R=3, W=3], anchor: "base")
    content((250, -180), small(fill: slate)[Read: full row. Write: full column.], anchor: "base")
    content((710, -150), head[Majority: R=5, W=5], anchor: "base")
    content((710, -180), small(fill: slate)[Any five of the same six survivors.], anchor: "base")

    // Stagger row and column outlines; each corner has equal node padding.
    for (col, x) in (210, 305, 400).enumerate() {
      quorum((x - 40, -230), 80, 280, kind: "write")
      content((x, -205), mono(fill: write-text, "col " + str(col + 1)), anchor: "base")
    }
    for (row, y) in (270, 370, 470).enumerate() {
      quorum((166, -y + 44), 278, 88)
      content((64, -y - 6), small(fill: read-text, "row " + str(row + 1)), anchor: "base-west")
    }
    for row in range(3) {
      for col in range(3) {
        let pos = (210 + 95 * col, -270 - 100 * row)
        let label = str(3 * row + col + 1)
        if row == col {
          failed-node(pos, label)
        } else {
          node(pos, label, r: node-radius)
        }
      }
    }

    // The majority outline encloses five live nodes and excludes node 8.
    // Its steps keep nodes 1, 5 and 9 outside the quorum as well.
    let majority = ((556, -236), (864, -236), (864, -334), (754, -334), (754, -434), (556, -434))
    line(..majority, close: true, stroke: quorum-pen("read"))
    content((710, -218), mono(fill: read-text)[quorum {2,3,4,6,7}], anchor: "base")
    for (y, labels) in ((280, (2, 3, 4)), (390, (6, 7, 8))) {
      for (col, label) in labels.enumerate() {
        node((600 + 110 * col, -y), str(label), r: node-radius)
      }
    }
    content((524, -496), tiny(fill: bad-text)[Failed], anchor: "base-west")
    for (col, label) in (1, 5, 9).enumerate() {
      failed-node((600 + 110 * col, -490), str(label))
    }

    note((64, -564), 372, kind: "blocked")[
      *Election and commit stop* \
      #small(fill: slate)[No complete read row or write column.]
    ]
    note((524, -564), 372, kind: "ok")[
      *Can elect and commit* \
      #small(fill: slate)[5 of 6 survivors form a quorum.]
    ]

    quorum((40, -642), 26, 18, radius: 4)
    content((78, -658), small(fill: read-text)[read quorum / majority], anchor: "base-west")
    quorum((350, -642), 26, 18, radius: 4, kind: "write")
    content((388, -658), small(fill: write-text)[write quorum], anchor: "base-west")
    cross((650, -651), size: 14)
    content((670, -657), small(fill: bad-text)[failed node], anchor: "base-west")
  },
)
