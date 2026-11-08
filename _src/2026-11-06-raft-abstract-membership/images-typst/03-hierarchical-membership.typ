#import "style.typ": *

#diagram(
  1000,
  660,
  "03. Select 2 sites, then 2 nodes at each selected site",
  "Sites A and B contribute nodes {1,2,4,5}: a write quorum of 4 nodes.",
  {
    card((400, -140), 200, 60, stroke: pen(write-ink, 2))[
      #head(fill: write-text)[2 of 3 sites]
    ]
    line((500, -200), (500, -245), stroke: pen(slate, 1.5))
    line((180, -245), (820, -245), stroke: pen(slate, 1.5))

    let sites = (
      (40, "site A", (1, 2, 3), true),
      (360, "site B", (4, 5, 6), true),
      (680, "site C", (7, 8, 9), false),
    )
    for (x, label, ids, selected) in sites {
      let center = x + 140
      let paint = if selected { write-ink } else { panel-line }
      let label-paint = if selected { write-text } else { slate }
      line((center, -245), (center, -280), stroke: pen(slate, 1.5))
      card((x, -280), 280, 300, fill: panel-fill, stroke: pen(paint, 1.5))
      content((center, -318), head(fill: label-paint, label), anchor: "base")
      card((x + 60, -350), 160, 50, fill: white, stroke: pen(panel-line, 1.5))[
        #small[2 of 3 nodes]
      ]
      line((center, -400), (center, -430), stroke: pen(slate, 1.5))
      line((x + 60, -430), (x + 220, -430), stroke: pen(slate, 1.5))
      for (index, id) in ids.enumerate() {
        let nx = x + 60 + index * 80
        line((nx, -430), (nx, -476), stroke: pen(slate, 1.5))
        node((nx, -500), str(id))
        if selected and index < 2 {
          ring((nx, -500), r: 32, paint: write-ink)
        }
      }
    }
    circle((58, -625), radius: 11, stroke: pen(write-ink, 3), fill: none)
    content((82, -631), small(fill: write-text)[Green marks the selected sites and nodes.], anchor: "base-west")
  },
)
