build:
	# Generate static site locally
	# Need to overrides url to generate site for another domain
	JEKYLL_ENV=production jekyll build \
		   --config _config.yml,_config_blog_openacid_com.yml || die

export: build
	# Convert built html to easy-to-publish versions:
	#   convert math and table to images
	python2 py/conv.py _site/algo/quorum
	python2 py/conv.py _site/algo/paxos
	python2 py/conv.py _site/tech/bla/programmer-should-know
	python2 py/conv.py _site/storage/ec-3
	python2 py/conv.py _site/storage/ec-2
	python2 py/conv.py _site/storage/ec-1
	python2 py/conv.py _site/culture/pr
	python2 py/conv.py _site/tech/cdn
	python2 py/conv.py _site/tech/zipf
	# put publish/ dir back to _site
	cp -R publish _site/
	# articles with all image uploaded
	cp -R import-back _site/
