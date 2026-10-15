#import "style.typ": *

#diagram(
  960,
  700,
  "08. Three phases: c0 → c01 → c1",
  "Commit c01 before appending c1. Shown: two-of-three quorums on each side.",
  {
    let phases = ((40, "1. c0", "Nodes 1-3"), (350, "2. c01", "Nodes 1-6"), (660, "3. c1", "Nodes 4-6"))
    for (x, title, members) in phases {
      panel((x, -110), 260, 430)
      content((x + 130, -150), head(title), anchor: "base")
      content((x + 130, -178), small(fill: slate, members), anchor: "base")
    }
    msg((309, -148), (341, -148))
    msg((619, -148), (651, -148))

    // c0: nodes 1-3.
    quorum((132, -272), 154, 84, kind: "write")
    quorum((54, -264), 154, 84)
    content((170, -210), mono(fill: read-text)[c0.read], anchor: "base")
    content((170, -240), mono(fill: read-text)[{1,2}], anchor: "base")
    node((100, -310), [1], r: 20)
    node((170, -310), [2], name: "c0-2", r: 20)
    node((240, -310), [3], r: 20)
    ring("c0-2", r: 28)
    content((170, -495), mono(fill: write-text)[c0.write], anchor: "base")
    content((170, -525), mono(fill: write-text)[{2,3}], anchor: "base")

    // c01: nodes 1-6; each joint quorum contains one quorum of c0 and one of c1.
    quorum((442, -272), 154, 194, kind: "write")
    quorum((364, -264), 154, 194)
    content((480, -207), mono(fill: read-text)[c01.read], anchor: "base")
    content((480, -228), mono(fill: read-text)[c0.read ∪ c1.read], anchor: "base")
    node((410, -310), [1], r: 20)
    node((480, -310), [2], name: "j-2", r: 20)
    node((550, -310), [3], r: 20)
    node((410, -420), [4], r: 20)
    node((480, -420), [5], name: "j-5", r: 20)
    node((550, -420), [6], r: 20)
    ring("j-2", r: 28)
    ring("j-5", r: 28)
    content((480, -495), mono(fill: write-text)[c01.write], anchor: "base")
    content((480, -525), mono(fill: write-text)[c0.write ∪ c1.write], anchor: "base")

    // c1: nodes 4-6.
    quorum((752, -382), 154, 84, kind: "write")
    quorum((674, -374), 154, 84)
    content((790, -210), mono(fill: read-text)[c1.read], anchor: "base")
    content((790, -240), mono(fill: read-text)[{4,5}], anchor: "base")
    node((720, -420), [4], r: 20)
    node((790, -420), [5], name: "c1-5", r: 20)
    node((860, -420), [6], r: 20)
    ring("c1-5", r: 28)
    content((790, -495), mono(fill: write-text)[c1.write], anchor: "base")
    content((790, -525), mono(fill: write-text)[{5,6}], anchor: "base")

    note((40, -575), 880, kind: "shared")[*Adjacent phases share log nodes*]
    content((68, -625), mono[c0.read ∩ c01.write = {2}], anchor: "base-west")
    content((68, -660), mono[c0.write ∩ c01.read = {2}], anchor: "base-west")
    content((508, -625), mono[c01.read ∩ c1.write = {5}], anchor: "base-west")
    content((508, -660), mono[c01.write ∩ c1.read = {5}], anchor: "base-west")
  },
)
