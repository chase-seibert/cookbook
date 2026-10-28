#!/usr/bin/env python3
"""Validate one cookbook recipe Markdown file."""
import argparse
import sys
from recipe_markdown import validate_recipe


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recipe_md", help="path to one .md recipe")
    args = parser.parse_args()
    try:
        recipe = validate_recipe(args.recipe_md)
    except (OSError, ValueError) as error:
        print(f"recipe Markdown error: {error}", file=sys.stderr)
        return 1
    print(f"{args.recipe_md}: valid ({recipe.recipe_id}, {len(recipe.blocks)} ordered content blocks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
