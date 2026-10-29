#!/usr/bin/env python3
"""Generate the plain-flow cookbook HTML from recipes/*.md."""

from __future__ import annotations

import argparse
from datetime import date
import sys
from html import escape
from pathlib import Path
from cookbook_index import ROOT, load_index
from recipe_markdown import Recipe, validate_recipe


def recipe_html(recipe: Recipe) -> str:
    """Render a recipe with the simple headings and breaks used by the old site."""
    out = [f'<h2 id="{escape(recipe.recipe_id, quote=True)}">{escape(recipe.title)}</h2>']
    for block in recipe.blocks:
        kind = block["type"]
        if kind == "subsection":
            out.append(f'<h3>{escape(block["text"])}</h3>')
        elif kind in {"intro", "tip"}:
            out.append(f'{escape(block["text"])}<br><br>')
        elif kind == "healthier":
            out.append(f'<br><br><i>Healthier option: {escape(block["text"])}</i>')
        elif kind in {"ingredients", "schedule"}:
            for first, second in block["rows"]:
                line = " ".join(part for part in (first, second) if part)
                out.append(f'&nbsp;&nbsp;&nbsp;{escape(line)}<br>')
            # Each ingredient line already ends in <br>; one more break gives
            # the two-break paragraph gap used by the legacy HTML renderer.
            out.append("<br>")
        elif kind == "step":
            out.append(f'{escape(block["text"])}<br><br>')
        elif kind == "pagebreak":
            # The legacy HTML renderer ignored LaTeX page breaks.
            continue
        else:
            raise ValueError(f"unsupported content block {kind!r}")
    return "\n".join(out)


def generate() -> str:
    categories, entries = load_index()
    recipes: dict[str, Recipe] = {
        slug: validate_recipe(ROOT / "recipes" / f"{slug}.md")
        for slug, _ in entries
    }

    out = [
        '<meta charset="utf-8" />',
        "<title>Chase Seibert's Cookbook</title>",
        '<div style="font-size: 200%">',
        "<h1>Chase Seibert's Cookbook</h1>",
        "From <a href='https://github.com/chase-seibert/cookbook'>",
        "https://github.com/chase-seibert/cookbook</a><br>",
        f"<i>Last updated: {date.today().isoformat()}</i><br>",
    ]
    for category in categories:
        out.append(f'<h2>{escape(category["title"])}</h2>')
        for slug in category["recipes"]:
            recipe = recipes[slug]
            out.append(
                f'<a href="#{escape(recipe.recipe_id, quote=True)}">'
                f'{escape(recipe.title)}</a><br>'
            )
    out.extend(["<br><hr>"])
    out.extend(recipe_html(recipes[slug]) for slug, _ in entries)
    out.extend(["</div>", ""])
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="build/html/Cookbook.html", help="full HTML output path")
    args = parser.parse_args()
    target = ROOT / args.output
    try:
        html = generate()
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(html, encoding="utf-8")
    except (OSError, ValueError) as error:
        print(f"HTML generation error: {error}", file=sys.stderr)
        return 1
    print(f"Generated Markdown cookbook HTML at {target.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
