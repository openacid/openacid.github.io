X_SVG2 := x-svg2

SVG_FILES := $(wildcard *.svg)
PNG_FILES := $(SVG_FILES:.svg=.png)

.PHONY: all png clean

all: png

png: $(PNG_FILES)

%.png: %.svg
	$(X_SVG2) $< -o $@

clean:
	rm -f $(PNG_FILES)
