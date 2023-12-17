#!/bin/sh

# fn="$(ls _posts/*$1* | head -n1)"

# if [ "$fn." = "." ]; then
#     echo "Usage: $0 <fn_pattern>"
#     exit 1
# fi



# for platform in wechat simple; do
#     md2zhihu \
#         -r git@gitee.com:drdrxp/bed.git@openacid \
#         -p $platform \
#         --keep-meta \
#         --code-width 600 \
#         $fn \
#         -o ${fn%.md}-$platform.md

# done


# === Build for copying to other platform only ===
#
# The assets do not need to be kept after publishing on other platforms.

# Call xp-md2html to convert md to html, using github-markdown.css
# xp-md2html is my local rust repo
md2html()
{
    local src_path="$1"
    local output_path="$2"

    # TODO: add original link

    {
        cat <<-END

<!doctype html>
<html>
<head>
<meta charset='UTF-8'>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="github-markdown.css">
<style>
	.markdown-body {
		box-sizing: border-box;
		min-width: 200px;
		max-width: 980px;
		margin: 0 auto;
		padding: 45px;
	}

	@media (max-width: 767px) {
		.markdown-body {
			padding: 15px;
		}
	}
</style>
</head>
<body>
<article class="markdown-body">
END

        # skip '---'
        cat "$src_path" | xp-md2html

        cat <<-END
<img src="qrcode-hori.jpg" />
</article>
</body>
</html>
END

    } > "$output_path"
}

# for example:
# https://pub-e254240c5c35410cb21a0cf4fb58f73e.r2.dev/2023-12-17-openraft-read.html
url_base="https://pub-e254240c5c35410cb21a0cf4fb58f73e.r2.dev"



fn=_src/openraft-read/2023-12-17-openraft-read.md
name=${fn##*/}
name=${name%.md}
title=${name#20??-??-??-}

echo "fn: $fn"
echo "name: $name"
echo "title: $title"


# Build local markdown
mkdir -p md2-local

# reference local resource
platform=wechat
md2zhihu \
    --platform         $platform \
    --code-width       600 \
    --refs             _data/refs.yml \
    --output-dir       ./md2-local \
    --asset-output-dir ./md2-local/ \
    --md-output        ./md2-local/$name.md \
    $fn

# reference remote resource
md2zhihu \
    --platform         $platform \
    --code-width       600 \
    --refs             _data/refs.yml \
    --output-dir       ./md2-local \
    --asset-output-dir ./md2-local/ \
    --md-output        ./md2-local/$name-remote.md \
    --rewrite          "^$title/" "$url_base/$title/" \
    $fn

cp assets/images/qrcode-hori.jpg ./md2-local/
cp assets/css/github-markdown.css ./md2-local/

# Build html
md2html "./md2-local/$name.md" "./md2-local/$name.html"
md2html "./md2-local/$name-remote.md" "./md2-local/$name-remote.html"

# Upload
aws s3 sync ./md2-local/ s3://bed/

echo ""
echo "$url_base/$name.html"
echo "$url_base/$name-remote.html"

exit 0

# Build zhihu specific md
#
# Usage: import md to zhihu

platform=zhihu
md2zhihu \
    --platform         $platform \
    --code-width       600 \
    --refs             _data/refs.yml \
    --output-dir       ./md2-$platform \
    --asset-output-dir ./md2-$platform/ \
    --md-output        ./md2-$platform/ \
    --repo             git@gitee.com:drdrxp/bed.git@openacid-$platform-import-assets \
    $fn


# Build wechat specific html.
# Render it to the last article.
# 
# Usage: push and let github build it and copy the html on a browser.

platform=wechat
md2zhihu \
    --platform         $platform \
    --code-width       600 \
    --refs             _data/refs.yml \
    --keep-meta \
    --output-dir       ./md2-$platform \
    --asset-output-dir ./md2-$platform/ \
    --md-output        ./_posts/2000-01-01-wechat-import.md \
    --repo             git@gitee.com:drdrxp/bed.git@openacid-$platform-import-assets \
    $fn


