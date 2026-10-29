#!/usr/bin/env python3
"""Generate the complete LaTeX cookbook from recipes/*.md."""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

from cookbook_index import ROOT, load_index
from recipe_markdown import render_latex, validate_recipe


PREAMBLE = r"""\documentclass[landscape,12pt,openany]{book}

\usepackage{multicol}
\usepackage{tabularx}
\usepackage{graphicx}
\graphicspath{{../../images/}}
\usepackage[margin=.75in,paperwidth=8.5in,paperheight=11in]{geometry}
\usepackage{titlesec}
\usepackage{xfrac}
\usepackage{mdframed}
\usepackage{gensymb}
\usepackage[abs]{overpic}
\setlength\unitlength{1in}
\usepackage{color}
\usepackage{cookbook}

\titlespacing*{\chapter}{0em}{-3em}{1em}
\titleformat{\chapter}{\normalfont\huge\bfseries}{\chaptertitlename\thechapter:}{20pt}{\Huge}
\renewcommand{\thesection}{}
\titleformat{\section}[block]{\titlerule\scshape\large\filcenter\vspace{2pt}}{}{0em}{}[\titlerule]
\titleformat{\subsection}[block]{\scshape\large\filcenter}{}{0em}{}[\titlerule]
\setlength{\parindent}{0em}
\setlength{\columnseprule}{0.4pt}
\pagestyle{plain}
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{hyperref}
\hypersetup{
    colorlinks=true,
    linkcolor=blue,
    filecolor=magenta,
    urlcolor=cyan,
    pdftitle={Chase Seibert's Cookbook},
    pdfpagemode=FullScreen,
    pdfstartpage=1,
}
\urlstyle{same}

\begin{document}
\rmfamily
\setlength{\columnseprule}{0pt}
\columnsep=2em
\setcounter{tocdepth}{1}
\small
\tableofcontents
\normalsize
\setlength{\parskip}{.5em}
"""


def generate(output_directory: Path) -> tuple[int, int]:
    categories, entries = load_index()
    recipe_directory = output_directory / "recipes"
    recipe_directory.mkdir(parents=True, exist_ok=True)
    for slug, _ in entries:
        recipe = validate_recipe(ROOT / "recipes" / f"{slug}.md")
        (recipe_directory / f"{slug}.tex").write_text(render_latex(recipe), encoding="utf-8")

    for stale in recipe_directory.glob("*.tex"):
        if stale.stem not in {slug for slug, _ in entries}:
            stale.unlink()

    master = [PREAMBLE]
    for category in categories:
        master.append(rf"\chapter{{{category['title']}}}")
        master.extend(rf"\input{{recipes/{slug}}}" for slug in category["recipes"])
        master.append("")
    master.append(r"\end{document}")
    master.append("")
    (output_directory / "Cookbook.tex").write_text("\n".join(master), encoding="utf-8")
    shutil.copy2(ROOT / "cookbook.sty", output_directory / "cookbook.sty")
    return len(entries), len(categories)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default="build/latex", help="generated LaTeX directory")
    args = parser.parse_args()
    target = (ROOT / args.output_dir).resolve()
    try:
        source_files, category_count = generate(target)
    except (OSError, ValueError) as error:
        print(f"LaTeX generation error: {error}", file=sys.stderr)
        return 1
    print(f"Generated {source_files} recipe LaTeX files and a cookbook index in {target.relative_to(ROOT)} ({category_count} categories)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
