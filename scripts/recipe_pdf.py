#!/usr/bin/env python3
"""Prepare and check a PDF preview for one Markdown-indexed recipe."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from cookbook_index import ROOT, load_index, subsection_slug
from recipe_markdown import validate_recipe

OUTPUT_DIRECTORY = ROOT / "build/recipe-pdf"
LATEX_DIRECTORY = ROOT / "build/latex"


def resolve_recipe(value: str) -> tuple[str, str]:
    if not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise ValueError("recipe must be a recipe ID or source slug without an extension")
    _, entries = load_index()
    for slug, _ in entries:
        recipe = validate_recipe(ROOT / "recipes" / f"{slug}.md")
        source_path = LATEX_DIRECTORY / "recipes" / f"{slug}.tex"
        if not source_path.is_file():
            raise ValueError(f"generated LaTeX source is missing; run make latex first ({source_path.relative_to(ROOT)})")
        source = source_path.read_text(encoding="utf-8")
        if recipe.kind != "collection":
            if value in {slug, recipe.recipe_id}:
                return recipe.recipe_id, source
            continue
        headings = list(re.finditer(r"\\subsection\s*\{([^{}]+)\}", source))
        recipe_end = source.find(r"\end{recipe}")
        if recipe_end < 0:
            raise ValueError(f"{source_path.relative_to(ROOT)} has no recipe terminator")
        for position, heading in enumerate(headings):
            recipe_id = f"{recipe.recipe_id}-{subsection_slug(heading.group(1))}"
            if value != recipe_id:
                continue
            next_heading = headings[position + 1].start() if position + 1 < len(headings) else recipe_end
            prefix = source[:headings[0].start()]
            body = source[heading.start():next_heading]
            trailer = source[recipe_end:]
            return recipe_id, prefix + body + trailer
    raise ValueError(f"{value!r} is not listed in recipes/index.json")


def prepare(recipe_id: str, recipe_source: str) -> Path:
    master_path = LATEX_DIRECTORY / "Cookbook.tex"
    if not master_path.is_file():
        raise ValueError("generated LaTeX cookbook is missing; run make latex first")
    master = master_path.read_text(encoding="utf-8")
    preamble, separator, _ = master.partition(r"\begin{document}")
    if not separator:
        raise ValueError("generated Cookbook.tex has no document body")
    OUTPUT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    recipe_file = OUTPUT_DIRECTORY / f"{recipe_id}-source.tex"
    recipe_file.write_text(recipe_source, encoding="utf-8")
    wrapper = OUTPUT_DIRECTORY / f"{recipe_id}-preview.tex"
    wrapper.write_text(
        preamble
        + r"\begin{document}" + "\n"
        + r"\rmfamily" + "\n"
        + r"\setlength{\columnseprule}{0pt}" + "\n"
        + r"\columnsep=2em" + "\n"
        + r"\setlength{\parskip}{.5em}" + "\n"
        + rf"\input{{build/recipe-pdf/{recipe_id}-source}}" + "\n"
        + r"\end{document}" + "\n",
        encoding="utf-8",
    )
    print(wrapper.relative_to(ROOT))
    return wrapper


def check(recipe_id: str) -> int:
    log = OUTPUT_DIRECTORY / f"{recipe_id}-preview.log"
    if not log.is_file():
        raise ValueError(f"LaTeX log not found: {log.relative_to(ROOT)}")
    text = log.read_text(encoding="utf-8", errors="replace")
    counts = re.findall(r"Output written on .*?\((\d+) pages?,", text)
    if not counts:
        raise ValueError("could not read the PDF page count from the LaTeX log")
    pages = int(counts[-1])
    if pages != 1:
        print(f"{recipe_id} preview is {pages} pages; condense the recipe to one page and rerun make recipe-pdf.", file=sys.stderr)
        return 1
    pdf = OUTPUT_DIRECTORY / f"{recipe_id}-preview.pdf"
    if not pdf.is_file():
        raise ValueError(f"PDF not found: {pdf.relative_to(ROOT)}")
    print(f"{pdf.relative_to(ROOT)}: 1 page")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "check"))
    parser.add_argument("recipe")
    args = parser.parse_args()
    try:
        recipe_id, recipe_source = resolve_recipe(args.recipe)
        if args.action == "prepare":
            prepare(recipe_id, recipe_source)
            return 0
        return check(recipe_id)
    except (OSError, ValueError) as error:
        print(f"recipe PDF error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
