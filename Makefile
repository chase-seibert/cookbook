.PHONY: pdf html all

all: pdf html

pdf:
	pdflatex Cookbook.tex

html:
	./run_html.py --index Cookbook.tex > Cookbook.html
