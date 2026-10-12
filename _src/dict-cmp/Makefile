# convert dot to jpg

YAMLs = $(wildcard *.yaml)
JPGs = $(YAMLs:.yaml=.jpg)

all: $(JPGs) circle-2-3-step.jpg

circle-2-3-step.jpg: circle-2-3-step.dot
	cat $< | dot -Tjpg -o $@

%.jpg:%.yaml
	python2 tensor-product-dot.py $< | dot -Tjpg -o $@

clean:
	rm $(JPGs)
