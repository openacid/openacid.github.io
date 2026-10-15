#import "style.typ": *

#diagram(
  960,
  610,
  "01. Quorum intersections in a four-node grid",
  "A full row elects; a full column commits.",
  {
    // Grid: rows are read quorums, columns are write quorums.
    panel((40, -110), 510, 423)
    quorum((197, -192), 94, 254, kind: "write")
    quorum((372, -192), 94, 254, kind: "write")
    quorum((189, -184), 269, 94)
    quorum((189, -344), 269, 94)
    content((240, -156), small(fill: write-text)[write {1,3}], anchor: "base")
    content((415, -156), small(fill: write-text)[write {2,4}], anchor: "base")
    content((62, -241), small(fill: read-text)[read {1,2}], anchor: "base-west")
    content((62, -401), small(fill: read-text)[read {3,4}], anchor: "base-west")

    node((240, -235), [1])
    node((415, -235), [2], name: "n2")
    node((240, -395), [3])
    node((415, -395), [4])
    ring("n2", name: "shared")

    // Notes, linked to the shared node.
    line("shared.east", (548, -235), (548, -278), (558, -278), stroke: pen(panel-line, 1.5))
    content((594, -154), head[Across phases], anchor: "base-west")
    content((594, -188), [Every read quorum meets], anchor: "base-west")
    content((594, -214), [every write quorum.], anchor: "base-west")
    note((566, -262), 354, kind: "shared")[
      *Example: node 2 is shared* \
      #mono[read {1,2} + write {2,4}]
    ]
    content((594, -364), head[Within a phase], anchor: "base-west")
    content((594, -400), [Rows can be disjoint.], anchor: "base-west")
    content((594, -426), [Columns can be disjoint.], anchor: "base-west")

    // Legend.
    quorum((40, -555), 24, 17, radius: 4)
    content((76, -571), small(fill: read-text)[read quorum], anchor: "base-west")
    quorum((280, -555), 24, 17, radius: 4, kind: "write")
    content((316, -571), small(fill: write-text)[write quorum], anchor: "base-west")
  },
)
