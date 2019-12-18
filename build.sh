# Build and deploy to a site in china mainland.
# This is works only on xp's mac.
TARGET=~/xp/vcs/coding/drmingdrmer/drmingdrmer/

die()
{
    echo "$@"
    exit 1
}


# Need to overrides url to generate site for another domain
JEKYLL_ENV=production jekyll build \
    --config _config.yml,_config_blog_openacid_com.yml || die

cp -R _site/* $TARGET    || die
cd $TARGET               || die
git add .                || die
git ci -m 'update build' || die
git push coding master   || die

