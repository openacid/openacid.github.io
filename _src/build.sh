#!/bin/sh

path="$1"

base="$(git rev-parse --show-toplevel)"
echo "git root: ($base)"


fn="${path##*/}"
echo "article: $path"

md2zhihu \
    --platform   zhihu \
    --refs       "$base/_data/refs.yml" \
    --jekyll     \
    --output-dir "$base/post-res" \
    --md-output  "$base/_posts/$fn" \
    --rewrite    "^../post-res/" "/post-res/" \
    $path
