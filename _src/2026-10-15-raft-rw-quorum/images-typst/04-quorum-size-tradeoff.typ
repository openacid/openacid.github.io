#import "style.typ": *

#diagram(
  960,
  680,
  "04. Read quorums intersect in a four-node grid",
  "Each read quorum contains one full row and one full column.",
  {
    // Read A is row {1,2} plus column {1,3}; read B is row {3,4} plus column {2,4}.
    panel((40, -110), 500, 430)
    let read-a = ((156, -196), (444, -196), (444, -284), (244, -284), (244, -484), (156, -484))
    let read-b = ((360, -200), (440, -200), (440, -480), (160, -480), (160, -400), (360, -400))
    line(..read-a, close: true, stroke: quorum-pen("read"))
    line(..read-b, close: true, stroke: quorum-pen("read", dashed: true))
    line((68, -151), (108, -151), stroke: pen(read-ink, 2.2))
    content((120, -157), mono(fill: read-text)[read A {1,2,3}], anchor: "base-west")
    line((68, -506), (108, -506), stroke: pen(read-ink, 2.2, dash: quorum-dash))
    content((120, -512), mono(fill: read-text)[read B {2,3,4}], anchor: "base-west")

    node((200, -240), [1], r: 23)
    node((400, -240), [2], name: "n2", r: 23)
    node((200, -440), [3], name: "n3", r: 23)
    node((400, -440), [4], r: 23)
    ring("n2", r: 32)
    ring("n3", r: 32)

    content((584, -154), head[Read/read intersection], anchor: "base-west")
    note((556, -214), 364, kind: "shared")[
      *Shared nodes: 2 and 3* \
      #mono[A ∩ B = {2,3}]
    ]
    content((584, -330), [Each shared node votes], anchor: "base-west")
    content((584, -358), [once per term.], anchor: "base-west")
    note((556, -410), 364, kind: "ok")[
      Only one candidate per term \
      can complete a read quorum.
    ]

    note((40, -574), 880, kind: "read")[Read: 3 nodes (row + column).]
    note((40, -614), 880, kind: "write")[Write: 2 nodes (one column).]
  },
)
