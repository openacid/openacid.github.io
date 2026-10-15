#import "style.typ": *

#diagram(
  960,
  760,
  "03. Original Raft with grid quorums: both commands commit",
  "Disjoint read quorums break the assumption of one leader per term.",
  {
    // Election: each row elects its own leader in the same term.
    panel((40, -110), 420, 560)
    content((64, -152), head("1. Election in term t"), anchor: "base-west")
    quorum((72, -203), 356, 156)
    quorum((72, -377), 356, 156)
    content((250, -245), small(fill: read-text)[read {1,2}], anchor: "base")
    content((250, -419), small(fill: read-text)[read {3,4}], anchor: "base")

    node((150, -281), [1], name: "l1", r: 26, leader: true)
    node((350, -281), [2], name: "l2")
    node((150, -455), [3], name: "l3")
    node((350, -455), [4], name: "l4", r: 26, leader: true)
    badge("l1")
    badge("l4")
    content((150, -331), mono("voted_for=1"), anchor: "base")
    content((350, -331), mono("voted_for=1"), anchor: "base")
    content((150, -505), mono("voted_for=4"), anchor: "base")
    content((350, -505), mono("voted_for=4"), anchor: "base")

    msg("l2", "l1", kind: "read", name: "vote-1")
    msg("l3", "l4", kind: "read", name: "vote-4")
    content("vote-1.mid", small(fill: read-text)[vote for 1], anchor: "south", padding: 8)
    content("vote-4.mid", small(fill: read-text)[vote for 4], anchor: "south", padding: 8)
    content((150, -374), small(fill: ok-text)[Leader 1 elected], anchor: "base")
    content((350, -553), small(fill: ok-text)[Leader 4 elected], anchor: "base")
    note((65, -600), 370)[Two leaders; same term t.]

    // AppendEntries: each leader also wins the other leader's voter.
    panel((500, -110), 420, 560)
    msg((468, -148), (492, -148))
    content((524, -152), head("2. AppendEntries at index i"), anchor: "base-west")
    content((524, -186), small(fill: slate)[Same term; matching log prefix], anchor: "base-west")
    quorum((552, -223), 116, 290, kind: "write")
    quorum((752, -223), 116, 290, kind: "write")

    node((610, -281), [1], name: "r1", r: 26, leader: true)
    node((810, -281), [2], name: "r2")
    node((610, -455), [3], name: "r3")
    node((810, -455), [4], name: "r4", r: 26, leader: true)
    badge("r1")
    badge("r4", side: "east", gap: 10)
    content((610, -210), mono("i: a"), anchor: "base")
    content((810, -241), mono("i: b"), anchor: "base")
    content((610, -503), mono("i: a"), anchor: "base")
    content((810, -503), mono("i: b"), anchor: "base")

    msg("r1.south", "r3.north", kind: "write", shift: (-14, 0))
    msg("r3.north", "r1.south", kind: "ok", reply: true, shift: (14, 0))
    content((640, -361), mono(fill: write-text)[a, term t], anchor: "base-west")
    content((642, -398), small(fill: ok-text)[OK], anchor: "base-west")
    msg("r4.north", "r2.south", kind: "write", shift: (-14, 0))
    msg("r2.south", "r4.north", kind: "ok", reply: true, shift: (14, 0))
    content((780, -383), mono(fill: write-text)[b, term t], anchor: "base-east")
    content((842, -361), small(fill: ok-text)[OK], anchor: "base-west")

    content((610, -565), mono(fill: write-text)[{1,3}: a], anchor: "base")
    content((810, -565), mono(fill: write-text)[{2,4}: b], anchor: "base")
    content((610, -599), text(fill: ok-text)[Leader 1 commits a], anchor: "base")
    content((810, -599), text(fill: ok-text)[Leader 4 commits b], anchor: "base")
    content((610, -628), small(fill: ok-text)[and executes a], anchor: "base")
    content((810, -628), small(fill: ok-text)[and executes b], anchor: "base")

    note((40, -704), 880, kind: "error")[*Leaders 1 and 4 execute different commands at the same index i.*]
  },
)
