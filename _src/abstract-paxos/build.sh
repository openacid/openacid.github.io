#!/bin/sh


a="$1"

base="$(git rev-parse --show-toplevel)"
echo "git root: ($base)"


a="${a##*/}"
echo "article: $a"

# TODO: add and use a standard platform specific for jekyll
#
md2zhihu \
    --platform   zhihu \
    --refs       "$base/_data/refs.yml" \
    --jekyll     \
    --output-dir "$base/post-res" \
    --md-output  "$base/_posts/$a" \
    --rewrite    "^../post-res/" "/post-res/" \
    $a
