# Keep the PDF builder on the same full TeX Live image used by
# xu-cheng/latex-action@v2 in GitHub Actions.
FROM ghcr.io/xu-cheng/texlive-full:latest

WORKDIR /work

# The upstream action provides its own entrypoint. Local development needs to
# invoke latexmk directly instead.
ENTRYPOINT []
