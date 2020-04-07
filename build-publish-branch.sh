#!/bin/sh

die()
{
    echo "$@"
    exit 1;
}

rm -rf _site/*

make export || die make

git add _site -f || die add

tree=$(git write-tree --prefix=_site) || die get tree

msg="publish: $(date) $(git log -n1 --format="%s")"

commit=$(echo "$msg" | git commit-tree $tree -p publish)
git update-ref refs/heads/publish $commit || die update-ref

git reset _site
