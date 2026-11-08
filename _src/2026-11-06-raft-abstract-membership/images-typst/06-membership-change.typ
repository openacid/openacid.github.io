#import "style.typ": *

#diagram(
  1100,
  630,
  "06. Membership change: C_old → joint → C_new",
  "Joint combines the old and new rules with AND; lines mark required intersections.",
  {
    let phases = ((40, "C_old"), (420, "joint"), (800, "C_new"))
    for (x, label) in phases {
      panel((x, -120), 260, 450)
      content((x + 130, -165), head(label), anchor: "base")
      line((x + 130, -300), (x + 130, -440), stroke: pen(slate, 1.8))
    }
    msg((310, -157), (410, -157))
    msg((690, -157), (790, -157))

    // Each crossing contains two independent read/write intersection links.
    for left in (280, 660) {
      line((left, -250), (left + 160, -490), stroke: pen(slate, 1.8))
      line((left, -490), (left + 160, -250), stroke: pen(slate, 1.8))
      circle((left + 80, -370), radius: 7, fill: white, stroke: none)
      line((left + 75, -377.5), (left + 85, -362.5), stroke: pen(slate, 1.8))
    }

    for (x, label) in ((60, "C_old"), (820, "C_new")) {
      quorum((x, -200), 220, 100)[#mono(fill: read-text, label + ".read")]
      quorum((x, -440), 220, 100, kind: "write")[#mono(fill: write-text, label + ".write")]
    }
    quorum((440, -200), 220, 100)[
      #set par(leading: 6 * px)
      #align(center)[
        #mono(fill: read-text, "C_old.read") \
        #tiny[AND] \
        #mono(fill: read-text, "C_new.read")
      ]
    ]
    quorum((440, -440), 220, 100, kind: "write")[
      #set par(leading: 6 * px)
      #align(center)[
        #mono(fill: write-text, "C_old.write") \
        #tiny[AND] \
        #mono(fill: write-text, "C_new.write")
      ]
    ]
    content((40, -608), small[Every line links a read quorum to a write quorum that it must intersect.], anchor: "base-west")
  },
)
