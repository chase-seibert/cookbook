.PHONY: pdf html docker-build docker-pdf docker-html docker all

DOCKER_PLATFORM ?= linux/amd64
DOCKER_IMAGE ?= cookbook-latex

all: pdf html

pdf:
	pdflatex Cookbook.tex

html:
	./run_html.py --index Cookbook.tex > Cookbook.html

docker-build:
	docker build --platform "$(DOCKER_PLATFORM)" --tag "$(DOCKER_IMAGE)" .

docker-pdf: docker-build
	docker run --rm --platform "$(DOCKER_PLATFORM)" --volume "$(PWD):/work" --workdir /work \
		--user "$(shell id -u):$(shell id -g)" --env HOME=/tmp "$(DOCKER_IMAGE)" \
		latexmk -pdf -interaction=nonstopmode -halt-on-error Cookbook.tex

docker-html:
	docker run --rm --volume "$(PWD):/work" --workdir /work python:3.13-slim \
		python3 run_html.py --index Cookbook.tex > Cookbook.html

docker: docker-pdf docker-html
