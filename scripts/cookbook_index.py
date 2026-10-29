"""Load and validate the Markdown cookbook's category and recipe order."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX_PATH = ROOT / "recipes/index.json"
RECIPES_DIRECTORY = ROOT / "recipes"


def load_index() -> tuple[list[dict], list[tuple[str, str]]]:
    data = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1 or not isinstance(data.get("categories"), list):
        raise ValueError(f"{INDEX_PATH}: expected schemaVersion 1 and a categories list")
    categories: list[dict] = []
    entries: list[tuple[str, str]] = []
    seen_categories: set[str] = set()
    seen_recipes: set[str] = set()
    for category in data["categories"]:
        if not isinstance(category, dict):
            raise ValueError(f"{INDEX_PATH}: category entries must be objects")
        title = category.get("title")
        slugs = category.get("recipes")
        if not isinstance(title, str) or not title.strip() or title in seen_categories:
            raise ValueError(f"{INDEX_PATH}: category titles must be non-empty and unique")
        if not isinstance(slugs, list) or not slugs:
            raise ValueError(f"{INDEX_PATH}: category {title!r} must list at least one recipe")
        seen_categories.add(title)
        normalized = []
        for slug in slugs:
            if not isinstance(slug, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", slug):
                raise ValueError(f"{INDEX_PATH}: invalid source slug in category {title!r}: {slug!r}")
            if slug in seen_recipes:
                raise ValueError(f"{INDEX_PATH}: duplicate recipe slug {slug!r}")
            if not (RECIPES_DIRECTORY / f"{slug}.md").is_file():
                raise ValueError(f"{INDEX_PATH}: missing Markdown recipe {slug}.md")
            seen_recipes.add(slug)
            entries.append((slug, title))
            normalized.append(slug)
        categories.append({"title": title, "recipes": normalized})
    indexed = {slug for slug, _ in entries}
    actual = {path.stem for path in RECIPES_DIRECTORY.glob("*.md")}
    missing = sorted(actual - indexed)
    unknown = sorted(indexed - actual)
    if missing or unknown:
        raise ValueError(f"{INDEX_PATH}: recipe index mismatch (unindexed={missing}, missing={unknown})")
    return categories, entries


def subsection_slug(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
