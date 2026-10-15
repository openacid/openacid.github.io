#import "style.typ": *

#diagram(
  960,
  800,
  "06. Ordered leader identities protect the log",
  "(t, 1) < (t, 4). The numbers on arrows show the message order.",
  {
    // Left: node 3 votes for (t,4) first, so it rejects the write from (t,1).
    panel((40, -110), 420, 480)
    content((64, -154), head[Vote before write], anchor: "base-west")
    content((150, -177), small[Leader 1], anchor: "base")
    content((150, -198), mono[(t, 1)], anchor: "base")
    quorum((106, -206), 96, 296, kind: "write")
    quorum((98, -398), 296, 96)

    node((150, -250), [1], name: "a1", leader: true)
    node((350, -250), [2])
    node((150, -450), [3], name: "a3")
    node((350, -450), [4], name: "a4", leader: true)
    ring("a3", r: 34, name: "a3-ring")

    msg("a4", "a3-ring", kind: "read")
    check((199, -432))
    content((250, -386), mono(fill: read-text, "1. Vote (t,4)"), anchor: "base")
    msg("a1", "a3-ring", kind: "write", head: "bad", name: "a-append")
    cross("a-append.end", size: 18)
    content((218, -322), mono(fill: write-text, "2. Append a"), anchor: "base-west")
    content((218, -350), small(fill: bad-text)[(t,1) rejected], anchor: "base-west")

    content((150, -529), mono[(t,4) recorded], anchor: "base")
    content((350, -529), small[Leader 4], anchor: "base")
    content((250, -555), mono(fill: read-text)[read {3,4}], anchor: "base")
    note((64, -624), 372, kind: "blocked")[
      *Node 1 cannot commit a* \
      #small(fill: slate)[write {1,3} is incomplete] \
      #small(fill: slate)[Full identity blocks the older write.]
    ]

    // Right: node 3 accepts a first, so its newer log rejects candidate 4.
    panel((500, -110), 420, 480)
    content((524, -154), head[Commit before vote], anchor: "base-west")
    content((610, -177), small[Leader 1], anchor: "base")
    content((610, -198), mono[(t, 1)], anchor: "base")
    quorum((566, -206), 96, 296, kind: "write")
    quorum((558, -398), 296, 96)

    node((610, -250), [1], name: "b1", leader: true)
    node((810, -250), [2])
    node((610, -450), [3], name: "b3")
    node((810, -450), [4], name: "b4")
    ring("b3", r: 34, name: "b3-ring")

    msg("b1", "b3-ring", kind: "write", name: "b-append")
    check("b-append.end")
    content((678, -322), mono(fill: write-text, "1. Commit a"), anchor: "base-west")
    content((678, -350), small[write {1,3}], anchor: "base-west")
    msg("b4", "b3-ring", kind: "read", head: "bad", name: "b-vote")
    cross("b-vote.end", size: 18)
    content((710, -386), mono(fill: read-text, "2. Vote (t,4)"), anchor: "base")

    content((610, -529), mono[(t,1,i): a], anchor: "base")
    content((810, -529), small[Candidate 4], anchor: "base")
    content((710, -555), mono(fill: read-text)[read {3,4}], anchor: "base")
    note((524, -624), 372, kind: "blocked")[
      *Node 4 cannot win this election* \
      #small(fill: slate)[Its log ends before index i.] \
      #small(fill: slate)[read {3,4} is incomplete] \
      #small(fill: slate)[Log freshness preserves committed a.]
    ]

    note((40, -750), 880)[#tiny(fill: slate)[Independent scenarios: identical starting logs; node 1 elected via read {1,2}.]]
  },
)
