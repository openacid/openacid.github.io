#import "style.typ": *

#diagram(
  960,
  800,
  "05. Small read quorums with dedicated election nodes",
  "Each read quorum uses one full row of log nodes and two of three election nodes.",
  {
    panel((40, -110), 880, 480)
    content((270, -145), head[Nodes 1-4 store logs], anchor: "base")
    content((750, -145), head[Election nodes], anchor: "base")

    // Write column {2,4}; each read quorum is a log row plus two election nodes.
    quorum((336, -196), 96, 356, kind: "write")
    quorum((108, -188), 316, 96)
    quorum((108, -448), 316, 96, dashed: true)
    quorum((586, -196), 208, 88)
    quorum((706, -196), 208, 88, dashed: true)
    line((424, -230), (586, -230), stroke: quorum-pen("read"))
    line((424, -500), (535, -500), (535, -268), (706, -268), stroke: quorum-pen("read", dashed: true))
    content((270, -177), mono(fill: read-text)[read {1,2,5,6}], anchor: "base")
    content((270, -579), mono(fill: read-text)[read {3,4,6,7}], anchor: "base")

    node((160, -240), [1], r: 23)
    node((380, -240), [2], name: "n2", r: 23)
    node((160, -500), [3], r: 23)
    node((380, -500), [4], name: "n4", r: 23)
    elect-node((630, -240), [5])
    elect-node((750, -240), [6], name: "n6")
    elect-node((870, -240), [7])
    ring("n2", r: 34)
    ring("n4", r: 34)
    ring("n6", r: 34)

    content((594, -326), head[Shared voter: node 6], anchor: "base-west")
    content((594, -365), small[One vote per term], anchor: "base-west")
    content((594, -394), small("Persists term and voted_for"), anchor: "base-west")
    content((594, -423), small[Receives no logs], anchor: "base-west")
    content((594, -480), small(fill: read-text)[read / read intersection], anchor: "base-west")
    content((594, -509), small[Node 6 keeps the leader unique.], anchor: "base-west")
    content((594, -542), mono(fill: write-text)[write {2,4}], anchor: "base-west")
    content((594, -571), small[Shares log nodes 2 and 4.], anchor: "base-west")

    // What each phase waits for.
    note((40, -624), 880, kind: "read")[
      *Election waits for 4 nodes* \
      #small(fill: slate)[2 log nodes + 2 election nodes]
    ]
    note((40, -684), 880, kind: "write")[
      *Commit waits for 2 log nodes* \
      #small(fill: slate)[One full column]
    ]

    note((40, -754), 880)[Read/read and read/write intersections serve different purposes.]
  },
)
