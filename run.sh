#!/bin/sh
set -eu
make docker-pdf
open build/latex/Cookbook.pdf
