#!/usr/bin/env python3
"""Convert one cookbook recipe Markdown file to a LaTeX recipe fragment."""
import argparse
import sys
from pathlib import Path
from recipe_markdown import render_latex, validate_recipe


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recipe_md")
    parser.add_argument("-o", "--output", help="output .tex path; stdout when omitted")
    args = parser.parse_args()
    try:
        result = render_latex(validate_recipe(args.recipe_md))
        if args.output:
            Path(args.output).write_text(result, encoding="utf-8")
        else:
            sys.stdout.write(result)
    except (OSError, ValueError) as error:
        print(f"Markdown to LaTeX error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
