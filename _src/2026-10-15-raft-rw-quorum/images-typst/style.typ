// Shared style and helpers for the raft-rw-quorum figures.
//
// One canvas unit is one SVG pixel. CeTZ's y axis points up, so a point
// that sits `y` pixels below the top edge is written as `(x, -y)`.

#import "@preview/cetz:0.5.2"
#import cetz.draw: *

#let px = 0.75pt

// Color usage:
// ink: titles, main labels, leader nodes and shared-node rings.
// slate: neutral facts, secondary labels, ordinary messages and phase transitions.
// panel-*: neutral scene backgrounds and separators; lifeline-ink: timeline guides.
// read-* (blue): read quorums, elections and phase-1 messages.
// write-* (green): write-quorum outlines, labels, annotations and log-replication arrows.
// ok-* (green): successful replies, completed operations and established guarantees.
// bad-* (red): actual errors or failures: rejected operations, failed nodes and safety violations.
// A difference from standard Raft is a neutral fact; use ink or slate.
// elect-*: dedicated election-node roles; white: page/node backgrounds and leader labels.
// Quorum groups use translucent outlines without fill; annotations have no frame or fill.
#let ink = rgb("#172b45")
#let slate = rgb("#52657a")
#let panel-fill = rgb("#f8fafc")
#let panel-line = rgb("#dbe3ec")
#let read-ink = rgb("#3068cf")
#let read-text = rgb("#2459b5")
#let write-ink = rgb("#238a55")
#let write-text = rgb("#176b40")
#let ok-ink = rgb("#277c53")
#let ok-text = rgb("#1b6a43")
#let bad-ink = rgb("#ba3b4a")
#let bad-text = rgb("#a62c3b")
#let bad-fill = rgb("#fff0f1")
#let elect-ink = rgb("#7656a0")
#let elect-fill = rgb("#f3f0fa")
#let lifeline-ink = rgb("#c6d0db")

// Text styles. Plain text is 20px Arial in `ink`.
#let sans = ("Arial", "Helvetica Neue")
#let head(fill: ink, it) = text(size: 22 * px, weight: "bold", fill: fill, it)
#let small(fill: ink, it) = text(size: 17 * px, fill: fill, it)
#let tiny(fill: ink, it) = text(size: 15 * px, fill: fill, it)
#let subtitle(it) = text(size: 18 * px, fill: slate, it)
#let mono(fill: ink, it) = text(font: "Menlo", size: 17 * px, fill: fill, it)

// A stroke `width` pixels wide.
#let pen(paint, width, dash: none) = (
  paint: paint,
  thickness: width * px,
  dash: dash,
  cap: "round",
  join: "round",
)

#let quorum-dash = (8 * px, 5 * px)
#let reply-dash = (6 * px, 4 * px)
#let lifeline-dash = (5 * px, 5 * px)

// A rectangle with its top-left corner at `pos`. A trailing content block
// is drawn at the rectangle's center; descenders do not shift it.
#let card(pos, w, h, radius: 14, fill: none, stroke: none, name: none, ..body) = {
  rect(pos, (rel: (w, -h)), radius: radius, fill: fill, stroke: stroke, name: name)
  for it in body.pos() {
    let label = text(top-edge: "cap-height", bottom-edge: "baseline", it)
    content((rel: (w / 2, -h / 2), to: pos), label)
  }
}

#let panel(pos, w, h, ..args) = card(pos, w, h, fill: panel-fill, stroke: pen(panel-line, 1.5), ..args)

#let note-styles = (
  info: (symbol: "ℹ️", paint: slate),
  shared: (symbol: "🔗", paint: ink),
  ok: (symbol: "✅", paint: ok-text),
  error: (symbol: "❌", paint: bad-text),
  blocked: (symbol: "⛔", paint: bad-text),
  read: (symbol: "🗳️", paint: read-text),
  write: (symbol: "📝", paint: write-text),
)

// An unframed annotation; wrapped lines align with the text, not the icon.
#let note(pos, w, body, kind: "info") = {
  let style = note-styles.at(kind)
  let icon = text(font: "Apple Color Emoji", size: 18 * px, style.symbol)
  let marker = std.move(dy: -4 * px, icon)
  let label = block({
    set text(size: 18 * px, fill: style.paint)
    set par(leading: 6 * px, spacing: 0pt)
    body
  })
  let layout = block(width: w * px, std.grid(
    columns: (20 * px, 1fr), column-gutter: 8 * px,
    align: top, marker, label,
  ))
  content(pos, layout, anchor: "north-west")
}

// The outline of a read or write quorum.
#let quorum-pen(kind, dashed: false) = {
  let paint = if kind == "read" { read-ink } else { write-ink }
  let dash = if dashed { quorum-dash } else { none }
  pen(paint.transparentize(40%), 2.5, dash: dash)
}

#let quorum(pos, w, h, kind: "read", dashed: false, ..args) = card(pos, w, h, stroke: quorum-pen(kind, dashed: dashed), ..args)

// A log node: a circle with its number at the center.
#let node(pos, label, name: none, r: 24, leader: false) = {
  let fill = if leader { ink } else { white }
  let stroke = if leader { pen(ink, 3) } else { pen(slate, 2) }
  let color = if leader { white } else { ink }
  circle(pos, radius: r, fill: fill, stroke: stroke, name: name)
  content(pos, text(size: 23 * px, weight: "bold", fill: color, label))
}

// An election-only node, drawn as a hexagon.
#let elect-node(pos, label, name: none) = {
  polygon(pos, 6, radius: 28, fill: elect-fill, stroke: pen(elect-ink, 2), name: name)
  content(pos, text(size: 23 * px, weight: "bold", label))
}

// A ring that marks a node shared by two quorums.
#let ring(node-name, r: 33, name: none) = circle(node-name, radius: r, stroke: pen(ink, 3), name: name)

// A "Leader" tag outside a node, `gap` pixels from its border on `side`.
#let badge(node-name, side: "north", gap: 5) = {
  let tag = box(
    width: 68 * px,
    height: 24 * px,
    fill: ink,
    radius: 7 * px,
    align(center + horizon, text(size: 15 * px, weight: "bold", fill: white)[Leader]),
  )
  let offset = (north: (0, gap), east: (gap, 0), south: (0, -gap), west: (-gap, 0)).at(side)
  let anchor = (north: "south", east: "west", south: "north", west: "east").at(side)
  content((rel: offset, to: node-name + "." + side), tag, anchor: anchor)
}

#let msg-paint = (ink: slate, read: read-ink, write: write-ink, ok: ok-ink, bad: bad-ink)

// An arrow from `a` to `b`; node names clip it at the node border.
// `head` colors the arrowhead differently, `reply` dashes the line, and
// `shift` moves both ends, so a request and its reply run side by side.
#let msg(a, b, kind: "ink", head: none, reply: false, shift: none, name: none) = {
  let paint = msg-paint.at(kind)
  let tip = msg-paint.at(if head == none { kind } else { head })
  let dash = if reply { reply-dash } else { none }
  let ends = if shift == none { (a, b) } else { ((rel: shift, to: a), (rel: shift, to: b)) }
  let mark = (end: ">", fill: tip, stroke: pen(tip, 1), length: 9, width: 8)
  line(..ends, stroke: pen(paint, 2.2, dash: dash), mark: mark, name: name)
}

// A check mark whose bottom corner is at `pos`.
#let check(pos) = line((rel: (-5, 5), to: pos), pos, (rel: (10, 12), to: pos), stroke: pen(ok-ink, 3))

// A cross centered at `pos`.
#let cross(pos, size: 12) = {
  let d = size / 2
  line((rel: (-d, d), to: pos), (rel: (d, -d), to: pos), stroke: pen(bad-ink, 3))
  line((rel: (-d, -d), to: pos), (rel: (d, d), to: pos), stroke: pen(bad-ink, 3))
}

// One figure: page setup, white background, title and subtitle.
#let diagram(w, h, title, sub, body) = {
  set page(width: auto, height: auto, margin: 0pt)
  set text(font: sans, size: 20 * px, fill: ink)
  cetz.canvas(length: px, {
    rect((0, 0), (w, -h), fill: white, stroke: none)
    content((40, -45), text(weight: "semibold", title), anchor: "base-west")
    content((40, -77), subtitle(sub), anchor: "base-west")
    body
  })
}
