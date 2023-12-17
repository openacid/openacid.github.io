#!/bin/sh

fn="$1"

base="$(git rev-parse --show-toplevel)"
echo "git root: ($base)"


fn="${fn##*/}"
echo "article: $fn"

md2zhihu \
    --platform   zhihu \
    --refs       "$base/_data/refs.yml" \
    --jekyll     \
    --output-dir "$base/post-res" \
    --md-output  "$base/_posts/$fn" \
    --rewrite    "^../post-res/" "/post-res/" \
    $fn
