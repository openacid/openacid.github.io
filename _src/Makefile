# Run from the repository root with: make -C _src
# Build each article's images-typst/NN-name.typ into images/NN-name.png (144 PPI).
# Needs typst >= 0.14, the minimum for CeTZ 0.5.2.

ARTICLES := $(patsubst %/images-typst,%,$(wildcard */images-typst))
TYP := $(wildcard */images-typst/[0-9]*.typ)
PNG := $(subst /images-typst/,/images/,$(TYP:.typ=.png))

all: $(PNG)

define article-images
$(1)/images/%.png: $(1)/images-typst/%.typ $(1)/images-typst/style.typ Makefile
	mkdir -p "$$(@D)"
	typst compile --ppi 144 "$$<" "$$@"
endef

$(foreach article,$(ARTICLES),$(eval $(call article-images,$(article))))

clean:
	rm -f $(PNG)

.PHONY: all clean
