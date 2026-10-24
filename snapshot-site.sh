#!/bin/sh

head_hash="$(git rev-parse HEAD)"

./convert-posts.sh

hugo build

cd public
git add .
git commit -m "Build from $head_hash"
