SRCS = $(wildcard src/*.md)
HTML = $(patsubst %.md, %.html, $(SRCS))

local: $(HTML)
	find src/ -regex '.*\.html' -exec sed -i "s|https://thomasnyberg.com|file://$(PWD)/src|g" {} \;

deploy: $(HTML)

%.html:%.md
	markdown $< > $@

clean:
	find src/ -regex '.*\.html' -exec rm -vf {} \;
