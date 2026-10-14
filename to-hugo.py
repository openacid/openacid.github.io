#!/usr/bin/env python3
"""Turn a post that md2zhihu wrote for Jekyll into a post for Hugo.

usage: to-hugo.py < <md2zhihu output> > <hugo input>

- It rewrites the math, so that Hugo's passthrough reads it as kramdown does.
  The passthrough copies the blockquote markers of each line into the math,
  and its math cannot span a blank line,
  so this script joins the lines of each math into one line.
  kramdown reads $$...$$ as block math when it fills its lines, starts after
  a blank line and ends before one, and as inline math elsewhere.
  This script writes each block math between \\[ and \\],
  which hugo.yaml sets as the block math delimiters.
"""
import re
import sys

# The blockquote markers and the indent that start a line.
CONTAINER = re.compile(r"[ \t>]*")
FENCE = re.compile(r"[ \t>]*(`{3,}|~{3,})")
CODE_SPAN = re.compile(r"(`+)(?!`).*?(?<!`)\1(?!`)")
DOLLARS = re.compile(r"\$\$")
ONE_MATH = re.compile(r"\$\$((?:(?!\$\$).)*)\$\$")
# A list item whose first line holds only math, which kramdown may read as block math.
LIST_ITEM_MATH = re.compile(r"[ \t>]*([-*+]|\d+[.)])[ \t]+\$\$((?!\$\$).)*\$\$[ \t]*")


def body_start(lines):
    """Return the index of the first body line, after the front matter."""
    if lines[0] != "---":
        raise ValueError("the post has no front matter")
    end = lines.index("---", 1)
    return end + 1


def container(line):
    return CONTAINER.match(line).group(0)


def is_blank(body, i):
    """Return if line i holds nothing but blockquote markers, or lies outside the body."""
    if i < 0 or i >= len(body):
        return True
    return body[i].strip(" \t>") == ""


def closes_fence(fence, line):
    marker = line.strip(" \t>")
    return marker != "" and set(marker) == {fence[0]} and len(marker) >= len(fence)


def dollar_count(line):
    """Return the number of $$ in a line, except those in a code span."""
    masked = CODE_SPAN.sub(lambda m: " " * len(m.group(0)), line)
    return len(DOLLARS.findall(masked))


def join_math_lines(body, i):
    """Join line i, whose last $$ opens math, with the lines up to the one that closes it.

    Return the joined line and the index of the closing line.
    """
    parts = [body[i].rstrip()]
    j = i
    while True:
        j += 1
        if j == len(body):
            raise ValueError(f"the $$ on body line {i + 1} is not closed: {body[i]!r}")
        text = body[j][len(container(body[j])) :].strip()
        if text != "":
            parts.append(text)
        if dollar_count(body[j]) > 0:
            return " ".join(parts), j


def as_block_math(line):
    """Return the line with its math between \\[ and \\], if the math fills the line, else None."""
    prefix = container(line)
    m = ONE_MATH.fullmatch(line[len(prefix) :].rstrip())
    if m is None:
        return None
    return prefix + "\\[" + m.group(1).strip() + "\\]"


def convert_math(body):
    out = []
    fence = None
    i = 0
    while i < len(body):
        line = body[i]
        opening = FENCE.match(line)
        if fence is not None:
            if closes_fence(fence, line):
                fence = None
            out.append(line)
            i += 1
            continue
        if opening is not None:
            fence = opening.group(1)
            out.append(line)
            i += 1
            continue
        j = i
        if dollar_count(line) % 2 == 1:
            line, j = join_math_lines(body, i)
        if LIST_ITEM_MATH.fullmatch(line):
            raise ValueError(f"math right after a list marker is not supported: {line!r}")
        block = None
        if is_blank(body, i - 1) and is_blank(body, j + 1):
            block = as_block_math(line)
        out.append(line if block is None else block)
        i = j + 1
    return out


def main():
    if len(sys.argv) != 1:
        sys.exit("usage: to-hugo.py < <md2zhihu output> > <hugo input>")
    lines = sys.stdin.read().split("\n")
    start = body_start(lines)
    body = convert_math(lines[start:])
    sys.stdout.write("\n".join(lines[:start] + body))


if __name__ == "__main__":
    main()
