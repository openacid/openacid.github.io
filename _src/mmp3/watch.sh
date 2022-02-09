#!/bin/sh

base="$(git rev-parse --show-toplevel)"
echo $base

fswatch *.md \
    | while read a; do

    a="${a##*/}"
    echo changed: $a

    md2zhihu \
        --platform   zhihu \
        --refs       "$base/_data/refs.yml" \
        --jekyll     \
        --rewrite    "^../post-res/" "/post-res/" \
        --output-dir "$base/post-res" \
        --md-output  "$base/_posts/$a" \
        $a
done
