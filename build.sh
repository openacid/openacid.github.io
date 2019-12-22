# Need to overrides url to generate site for another domain
JEKYLL_ENV=production jekyll build \
    --config _config.yml,_config_blog_openacid_com.yml || die
