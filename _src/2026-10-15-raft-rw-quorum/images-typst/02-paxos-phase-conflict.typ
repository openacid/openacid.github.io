#import "style.typ": *

#diagram(
  960,
  760,
  "02. Paxos: phase 2 resolves the conflict",
  "ballot_1 < ballot_4 | Both read quorums reply before either write.",
  {
    // Phase 1: each leader completes its own read quorum.
    panel((40, -110), 420, 560)
    content((64, -152), head("1. Phase 1: election"), anchor: "base-west")
    quorum((72, -203), 356, 156)
    quorum((72, -377), 356, 156)
    content((250, -235), small(fill: read-text)[read {1,2}], anchor: "base")
    content((250, -409), small(fill: read-text)[read {3,4}], anchor: "base")

    node((150, -281), [1], name: "l1", r: 26, leader: true)
    node((350, -281), [2], name: "l2")
    node((150, -455), [3], name: "l3")
    node((350, -455), [4], name: "l4", r: 26, leader: true)
    badge("l1")
    badge("l4")
    content((150, -331), mono("ballot_1"), anchor: "base")
    content((350, -331), mono("ballot_1"), anchor: "base")
    content((150, -505), mono("ballot_4"), anchor: "base")
    content((350, -505), mono("ballot_4"), anchor: "base")

    msg("l1.east", "l2.west", kind: "read", shift: (0, 10), name: "prepare-1")
    msg("l2.west", "l1.east", kind: "read", reply: true, shift: (0, -11), name: "promise-1")
    msg("l4.west", "l3.east", kind: "read", shift: (0, 10), name: "prepare-4")
    msg("l3.east", "l4.west", kind: "read", reply: true, shift: (0, -11), name: "promise-4")
    content("prepare-1.mid", small(fill: read-text)[Prepare], anchor: "south", padding: 10)
    content("promise-1.mid", small(fill: read-text)[Promise], anchor: "north", padding: 10)
    content("prepare-4.mid", small(fill: read-text)[Prepare], anchor: "south", padding: 10)
    content("promise-4.mid", small(fill: read-text)[Promise], anchor: "north", padding: 10)

    note((65, -600), 370)[Both leaders finish phase 1.]

    // Phase 2: node 3 rejects the lower ballot, so only leader 4 commits.
    panel((500, -110), 420, 560)
    msg((468, -148), (492, -148))
    content((524, -152), head("2. Phase 2: write at index i"), anchor: "base-west")
    content((524, -186), small(fill: slate)[Lower ballot rejected; higher ballot accepted], anchor: "base-west")
    quorum((552, -223), 116, 290, kind: "write")
    quorum((752, -223), 116, 290, kind: "write")

    node((610, -281), [1], name: "r1", r: 26, leader: true)
    node((810, -281), [2], name: "r2")
    node((610, -455), [3], name: "r3")
    node((810, -455), [4], name: "r4", r: 26, leader: true)
    badge("r1")
    badge("r4", side: "east", gap: 10)
    content((610, -210), mono("ballot_1"), anchor: "base")
    content((810, -241), mono("i: b"), anchor: "base")
    content((610, -503), small(fill: bad-text)[Reject a], anchor: "base")
    content((610, -535), mono("ballot_4"), anchor: "base")
    content((810, -503), mono("i: b"), anchor: "base")

    msg("r1.south", "r3.north", kind: "write", shift: (-14, 0))
    msg("r3.north", "r1.south", kind: "bad", reply: true, shift: (14, 0), name: "reject-a")
    cross("reject-a.end")
    content((640, -361), mono(fill: write-text)[a], anchor: "base-west")
    content((642, -398), small(fill: bad-text)[Reject], anchor: "base-west")

    msg("r4.north", "r2.south", kind: "write", shift: (-14, 0))
    msg("r2.south", "r4.north", kind: "ok", reply: true, shift: (14, 0), name: "accept-b")
    check("accept-b.end")
    content((780, -383), mono(fill: write-text)[b], anchor: "base-east")
    content((842, -361), small(fill: ok-text)[OK], anchor: "base-west")

    content((610, -583), mono(fill: write-text)[write {1,3}], anchor: "base")
    content((810, -583), mono(fill: write-text)[write {2,4}], anchor: "base")
    content((610, -612), text(fill: bad-text)[a not committed], anchor: "base")
    content((810, -612), text(fill: ok-text)[b committed], anchor: "base")
    content((610, -641), small("Node 3 promised ballot_4"), anchor: "base")
    content((810, -641), small[Nodes 2 and 4 accept], anchor: "base")

    note((40, -704), 880, kind: "ok")[*Only leader 4 can commit at index i.*]
  },
)
