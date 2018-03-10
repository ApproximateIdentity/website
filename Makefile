SRCS = $(wildcard src/*.md)
HTML = $(patsubst %.md, %.html, $(SRCS))

local: $(HTML)
	find src/ -regex '.*\.html' -exec sed -i "s|https://thomasnyberg.com|file://$(PWD)/src|g" {} \;

deploy: $(HTML)

%.html:%.md
	echo '<!doctype html><html lang=en><head><meta charset=utf-8><title>' > $@
	grep '^# ' $< | sed 's/^# //' >> $@
	echo '</title>' >> $@
	cat style.css >> $@
	echo '</head><body>' >> $@
	markdown $< >> $@
	echo '</body></html>' >> $@

clean:
	find src/ -regex '.*\.html' -exec rm -vf {} \;
