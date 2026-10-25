#!/usr/bin/env python3
"""Prepare and check a PDF preview for one indexed cookbook recipe."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX = ROOT / "Cookbook.tex"
METADATA = ROOT / "data/mobile/metadata.json"
OUTPUT_DIRECTORY = ROOT / "build/recipe-pdf"


def resolve_recipe(value: str) -> tuple[str, str]:
    if not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise ValueError("recipe must be a recipe ID or source slug without an extension")
    index = INDEX.read_text(encoding="utf-8")
    sources = re.findall(r"\\input\s*\{([^{}]+)\}", index)
    metadata = json.loads(METADATA.read_text(encoding="utf-8"))
    collections = set(metadata.get("recipeCollections", []))

    for source_slug in sources:
        path = ROOT / f"{source_slug}.tex"
        if not path.is_file():
            continue
        source = path.read_text(encoding="utf-8")
        stable_id = metadata.get("recipeIDs", {}).get(source_slug, source_slug)
        if source_slug not in collections:
            if value == stable_id or value == source_slug:
                return stable_id, source
            continue

        headings = list(re.finditer(r"\\subsection\s*\{([^{}]+)\}", source))
        end_recipe = source.find(r"\end{recipe}")
        if end_recipe < 0:
            continue
        for index_in_file, heading in enumerate(headings):
            subsection_slug = re.sub(r"[^a-z0-9]+", "-", heading.group(1).lower()).strip("-")
            recipe_id = f"{stable_id}-{subsection_slug}"
            if value != recipe_id:
                continue
            next_heading = headings[index_in_file + 1].start() if index_in_file + 1 < len(headings) else end_recipe
            prefix = source[:headings[0].start()]
            body = source[heading.start():next_heading]
            trailer = source[end_recipe:]
            return recipe_id, prefix + body + trailer

    raise ValueError(f"{value!r} is not a recipe included by Cookbook.tex")


def prepare(recipe_id: str, recipe_source: str) -> Path:
    source = INDEX.read_text(encoding="utf-8")
    preamble, separator, _ = source.partition(r"\begin{document}")
    if not separator:
        raise ValueError("Cookbook.tex has no document body")
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
        print(
            f"{recipe_id} preview is {pages} pages; condense the recipe to one page and rerun make recipe-pdf.",
            file=sys.stderr,
        )
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
