BIGs = $(wildcard *-big.jpg)
SMALLs = $(BIGs:-big.jpg=-small.jpg)
TAGs = $(BIGs:-big.jpg=-tag.html)

all: $(TAGs)

%-small.jpg:%-big.jpg
	convert -resize '25%%' $< $@

%-tag.html:%-small.jpg
	python2 todatauri.py $< > $@

clean:
	rm $(SMALLs) $(TAGs)
