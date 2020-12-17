build:
	# Generate static site locally
	# Need to overrides url to generate site for another domain
	JEKYLL_ENV=production jekyll build \
		   --config _config.yml,_config_blog_openacid_com.yml || die

export: build
	# Convert built html to easy-to-publish versions:
	#   convert math and table to images
	# python3 py/conv.py _site/algo/slimarray
	# python3 py/conv.py _site/algo/paxoskv
	python3 py/conv.py _site/algo/quorum
	# python3 py/conv.py _site/algo/paxos
	# python3 py/conv.py _site/tech/bla/programmer-should-know
	# python3 py/conv.py _site/storage/ec-3
	# python3 py/conv.py _site/storage/ec-2
	# python3 py/conv.py _site/storage/ec-1
	# python3 py/conv.py _site/culture/pr
	# python3 py/conv.py _site/tech/cdn
	# python3 py/conv.py _site/tech/zipf

	# put publish/ dir back to _site
	cp -R publish _site/
	# articles with all image uploaded
	cp -R import-back _site/
