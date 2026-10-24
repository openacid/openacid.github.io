#!/bin/sh

# === Build for copying to other platform only ===
#
# It looks like gitee no longer support external access with refer
# --repo             git@gitee.com:drdrxp/bed.git@openacid-$platform-import-assets \

set -o errexit

# for example:
# https://pub-e254240c5c35410cb21a0cf4fb58f73e.r2.dev/2023-12-17-openraft-read.html
url_base="https://pub-e254240c5c35410cb21a0cf4fb58f73e.r2.dev"

# Platforms that md2zhihu accepts, see: md2zhihu --help
md2zhihu_platforms="zhihu wechat weibo github minimal_mistake simple transparent"



# Call xpmd to convert md to html, using github-markdown.css
# xpmd is from xp-md2html, a personal repo
acid_md2html()
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

        xpmd render-markdown --bare -i "$src_path"

        cat <<-END
<img src="qrcode-hori.jpg" />
</article>
</body>
</html>
END

    } > "$output_path"
}


build()
{
    local platform="$1"
    local fn="$2"

    local supported=false
    local p
    for p in $md2zhihu_platforms; do
        if [ "$p" = "$platform" ]; then
            supported=true
        fi
    done

    if [ "$supported" = false ]; then
        echo "Invalid platform: '$platform', expect one of: $md2zhihu_platforms" >&2
        exit 1
    fi

    local name_suffix=${fn##*/}
    local name=${name_suffix%.md}
    # remove date
    local title=${name#20??-??-??-}

    echo ""
    echo "fn: $fn"
    echo "name: $name"
    echo "title: $title"
    echo ""

    # Build local markdown
    mkdir -p md2-local

    # reference local resource
    md2zhihu \
        --platform         $platform \
        --code-width       600 \
        --refs             _src/refs.yml \
        --output-dir       ./md2-local \
        --asset-output-dir ./md2-local/ \
        --md-output        ./md2-local/$name-$platform.md \
        $fn

    # reference remote resource
    md2zhihu \
        --platform         $platform \
        --code-width       600 \
        --refs             _src/refs.yml \
        --output-dir       ./md2-local \
        --asset-output-dir ./md2-local/ \
        --md-output        ./md2-local/$name-$platform-remote.md \
        --rewrite          "^$title/" "$url_base/$title/" \
        $fn

    cp static/assets/images/qrcode-hori.jpg ./md2-local/
    cp static/assets/css/github-markdown.css ./md2-local/

    # Build html
    acid_md2html "./md2-local/$name-$platform.md"        "./md2-local/$name-$platform.html"
    acid_md2html "./md2-local/$name-$platform-remote.md" "./md2-local/$name-$platform-remote.html"

    # Upload
    aws s3 sync ./md2-local/ s3://bed/

    echo "Built online md:"
    echo ""
    echo "    $url_base/$name-$platform.html"
    echo "    $url_base/$name-$platform-remote.html"
    echo ""
}

# build "wechat" _src/2026-08-01-ezraft/ezraft-cn.md
# build "zhihu" _src/2026-08-01-ezraft/ezraft-cn.md

# build "wechat" _src/2026-08-11-ez-ts-oracle/ez-ts-oracle-cn.md
# build "zhihu" _src/2026-08-11-ez-ts-oracle/ez-ts-oracle-cn.md

# build "wechat" _src/2026-10-15-raft-rw-quorum/raft-rw-quorum-cn.md
build $1 $2


