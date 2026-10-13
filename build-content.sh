#!/bin/sh
# Build the Hugo input in .build/ from the published posts in _src/.
# A source is published when its front matter sets permalink:.
# Each post goes into .build/<name>/ with its images.
#
# The script runs itself in the md2zhihu image, which has md2zhihu
# and the programs it runs, such as graphviz and mermaid-cli.

set -e
cd "$(dirname "$0")"

# Another md2zhihu version may write other output, so the version is fixed.
image=ghcr.io/drmingdrmer/md2zhihu:v0.19

if [ "$1" != "--in-image" ]; then
    exec docker run --rm -v "$PWD:/work" --user "$(id -u):$(id -g)" "$image" ./build-content.sh --in-image
fi

rm -rf .build

for path in $(grep -l '^permalink:' _src/*/*.md); do
    fn="${path##*/}"
    # md2zhihu names the image dir of a post by its file name.
    name="${fn%.md}"
    out=".build/$name/$fn"

    # The post and its images share a dir, so md2zhihu links an image by its file name.
    # The rewrite gives each image the URL it had on the Jekyll site.
    md2zhihu \
        --platform         minimal_mistake \
        --refs             _src/refs.yml \
        --jekyll           \
        --asset-output-dir .build \
        --md-output        "$out" \
        --rewrite          "^" "/post-res/$name/" \
        "$path"

    python3 to-hugo.py "$path" < "$out" > "$out.tmp"
    mv "$out.tmp" "$out"
done
