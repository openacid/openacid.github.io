TARGET = $(HOME)/xp/vcs/coding/drmingdrmer/drmingdrmer/
build:
	# Generate static site locally
	# Need to overrides url to generate site for another domain
	JEKYLL_ENV=production jekyll build \
		   --config _config.yml,_config_blog_openacid_com.yml || die

export: build
	# Convert built html to easy-to-publish versions:
	#   convert math and table to images
	python2 py/conv.py _site/tech/bla/programmer-should-know
	python2 py/conv.py _site/storage/ec-3
	python2 py/conv.py _site/storage/ec-2
	python2 py/conv.py _site/storage/ec-1
	python2 py/conv.py _site/culture/pr
	python2 py/conv.py _site/tech/cdn
	python2 py/conv.py _site/tech/zipf
	# put publish/ dir back to _site
	cp -R publish _site/

# Build and deploy to a site in china mainland.
# This is works only on xp's mac.
pub: export
	cp -R _site/* $(TARGET)
	git -C $(TARGET) add .
	git -C $(TARGET) ci -m 'update build'
	# git push coding master

