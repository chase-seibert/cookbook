# Chase Seibert's Cookbook

This is a collection of recipes in LaTeX format that I use to print a hard-copy version from Lulu.com.

[PDF version](https://www.dropbox.com/s/j16y65jm26780n8/cookbook.pdf?dl=0) available via Dropbox.


# Compile

*Note: you likely have to re-install every time OSX updates*

1. Install [MacTex](https://tug.org/mactex/)
2. Run `./run.sh`

If you get the error "the winder server could not be contacted", you need to run the script outside of tmux ;)

# Editing

- You can include a blank page with the following:

```
\newpage
\thispagestyle{empty}
\mbox{}
```

- You can break a column manually with:

```
\columnbreak
```
