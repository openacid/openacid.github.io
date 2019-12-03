# Build and deploy to a site in china mainland.
# This is works only on xp's mac.
TARGET=~/xp/vcs/coding/drmingdrmer/drmingdrmer/

die()
{
    echo "$@"
    exit 1
}

JEKYLL_ENV=production jekyll build || die
cp -R _site/* $TARGET || die
cd $TARGET || die
git add . || die
git ci -m 'update build' || die
git push coding master || die

