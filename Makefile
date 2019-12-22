TARGET = $(HOME)/xp/vcs/coding/drmingdrmer/drmingdrmer/
export:
	# Generate static site locally
	sh build.sh
	# Convert built html to easy-to-publish versions:
	#   convert math and table to images
	python2 py/conv.py _site/culture/pr
	python2 py/conv.py _site/tech/cdn
	python2 py/conv.py _site/tech/zipf
	# Re-generate to put publish/ dir back to _site
	sh build.sh

# Build and deploy to a site in china mainland.
# This is works only on xp's mac.
pub: export
	cp -R _site/* $(TARGET)
	git -C $(TARGET) add .
	git -C $(TARGET) ci -m 'update build'
	# git push coding master

