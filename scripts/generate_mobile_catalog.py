#!/usr/bin/env python3
"""Build an offline JSON catalog from the cookbook's LaTeX source."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
METADATA_PATH = ROOT / "data/mobile/metadata.json"
THUMBNAIL_MANIFEST_PATH = ROOT / "data/mobile/thumbnail-manifest.json"
THUMBNAIL_DIRECTORY = ROOT / "ios/Cookbook/Resources/Thumbnails"
FRACTIONS = {
    ("1", "2"): "½", ("1", "4"): "¼", ("1", "8"): "⅛",
    ("3", "4"): "¾", ("1", "3"): "⅓", ("2", "3"): "⅔",
}


def group(text: str, start: int) -> tuple[str, int]:
    """Return a balanced brace group beginning at start (the opening brace)."""
    if start >= len(text) or text[start] != "{":
        raise ValueError("expected opening brace")
    depth, i = 1, start + 1
    while i < len(text) and depth:
        if text[i] == "\\":
            i += 2
            continue
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    if depth:
        raise ValueError("unclosed brace group")
    return text[start + 1:i - 1], i


def commands(text: str, name: str) -> list[tuple[str, int, int]]:
    found = []
    pattern = re.compile(r"\\" + re.escape(name) + r"\s*\{")
    for match in pattern.finditer(text):
        try:
            body, end = group(text, match.end() - 1)
            found.append((body, match.start(), end))
        except ValueError as error:
            raise ValueError(f"\\{name}: {error}") from error
    return found


def clean(text: str) -> str:
    text = re.sub(r"%[^\n]*", "", text)
    text = text.replace("\\\\", "\n")
    text = text.replace("~", " ")
    text = re.sub(r"\\degree\s*\{\s*\}", "°", text)
    text = re.sub(r"\\degree\b", "°", text)
    for (n, d), glyph in FRACTIONS.items():
        text = text.replace(rf"\sfrac{{{n}}}{{{d}}}", glyph)
    text = re.sub(r"\\(textit|textbf|emph|underline)\s*\{([^{}]*)\}", r"\2", text)
    text = re.sub(r"\\([%&#_$])", r"\1", text)
    text = re.sub(r"\\[a-zA-Z]+\*?(?:\[[^]]*\])?", "", text)
    text = text.replace("{", "").replace("}", "")
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


def index_entries() -> list[tuple[str, str]]:
    index = (ROOT / "Cookbook.tex").read_text(encoding="utf-8")
    category = "Uncategorized"
    entries = []
    for line in index.splitlines():
        chapter = re.search(r"\\chapter\s*\{(.*?)\}", line)
        if chapter:
            category = clean(chapter.group(1))
        include = re.search(r"\\input\s*\{([^{}]+)\}", line)
        if include:
            entries.append((include.group(1), category))
    return entries


def parse_file(slug: str, category: str, metadata: dict) -> list[dict]:
    path = ROOT / f"{slug}.tex"
    if not path.is_file():
        raise ValueError(f"Cookbook.tex references missing file: {path.name}")
    source = path.read_text(encoding="utf-8")
    section_headings = [(m.start(), clean(m.group(1))) for m in re.finditer(r"\\section\s*\{([^{}]+)\}", source)]
    subsection_headings = [(m.start(), clean(m.group(1))) for m in re.finditer(r"\\subsection\s*\{([^{}]+)\}", source)]
    if not section_headings:
        raise ValueError(f"{path.name}: missing \\section title")
    stable_file_id = metadata.get("recipeIDs", {}).get(slug, slug)
    collections = set(metadata.get("recipeCollections", []))
    if slug in collections:
        recipe_segments = []
        for i, (offset, title) in enumerate(subsection_headings):
            next_offsets = [pos for pos, _ in subsection_headings[i + 1:] if pos > offset]
            next_section = [pos for pos, _ in section_headings if pos > offset]
            end = min(next_offsets + next_section, default=len(source))
            recipe_segments.append((offset, end, title, f"{stable_file_id}-{re.sub('[^a-z0-9]+', '-', title.lower()).strip('-')}"))
    else:
        root_start, title = section_headings[0]
        recipe_segments = [(root_start, len(source), title, stable_file_id)]
    recipes = []
    for start, end, title, stable in recipe_segments:
        segment = source[start:end]
        local_subsections = [(offset - start, section_title) for offset, section_title in subsection_headings if start <= offset < end]
        ingredients = []
        ingredient_blocks = sorted(commands(segment, "ingredients") + commands(segment, "ingredientsLeft"), key=lambda item: item[1])
        ingredient_block_ids = []
        for match in ingredient_blocks:
            body = match[0]
            block_ids = []
            for line in body.splitlines():
                line = line.strip().rstrip("\\").strip()
                if not line or "&" not in line:
                    continue
                quantity, name = line.split("&", 1)
                name = clean(name)
                quantity = clean(quantity)
                if name:
                    ingredient_id = f"{stable}-ingredient-{len(ingredients)+1}"
                    override = metadata.get("ingredientOverrides", {}).get(ingredient_id, {})
                    staple_names = {" ".join(item.casefold().split()) for item in metadata.get("stapleGroceryNames", [])}
                    grocery_name = clean_grocery_name(override.get("groceryName", name))
                    normalized_grocery = " ".join(grocery_name.casefold().split())
                    staple_patterns = metadata.get("pantryStaplePatterns", [])
                    is_staple = normalized_grocery in staple_names or any(re.search(pattern, normalized_grocery, re.I) for pattern in staple_patterns)
                    is_excluded = normalized_grocery in {" ".join(item.casefold().split()) for item in metadata.get("excludedGroceryNames", [])}
                    ingredients.append({"id": ingredient_id, "quantity": quantity, "name": name, "groceryName": grocery_name, "staple": override.get("staple", is_staple), "excludeFromGroceries": override.get("excludeFromGroceries", is_excluded)})
                    block_ids.append(ingredient_id)
            ingredient_block_ids.append((match[2], block_ids))
        excluded = []
        for tag in ("section", "subsection", "ingredients", "ingredientsLeft", "pre", "tip", "healthierOption"):
            excluded.extend((a, b) for _, a, b in commands(segment, tag))
        excluded += [(m.start(), m.end()) for m in re.finditer(r"\\begin\s*\{[^}]+\}|\\end\s*\{[^}]+\}", segment)]
        excluded.sort()
        prose = []
        cursor = 0
        for a, b in excluded:
            if a < cursor:
                continue
            prose.append((cursor, segment[cursor:a]))
            cursor = b
        prose.append((cursor, segment[cursor:]))
        paragraphs = []
        for chunk_start, chunk in prose:
            boundaries = [m.span() for m in re.finditer(r"\n[ \t]*\n+", chunk)]
            paragraph_start = 0
            for boundary_start, boundary_end in boundaries + [(len(chunk), len(chunk))]:
                raw = chunk[paragraph_start:boundary_start]
                instruction = clean(raw)
                if instruction:
                    paragraphs.append((chunk_start + paragraph_start, instruction))
                paragraph_start = boundary_end
        steps = []
        for i, (offset, instruction) in enumerate(paragraphs):
            current_ids = next((ids for block_end, ids in reversed(ingredient_block_ids) if block_end <= offset), [])
            step_id = f"{stable}-step-{i+1}"
            assigned = metadata.get("stepIngredientIDs", {}).get(step_id, current_ids)
            section_title = next((name for heading_offset, name in reversed(local_subsections) if heading_offset <= offset), "")
            steps.append({"id": step_id, "sectionTitle": section_title, "instruction": instruction, "originalInstruction": instruction, "ingredientIDs": assigned, "durationMinutes": None, "active": True})
        def first(tag: str) -> str:
            values = commands(segment, tag)
            return clean(values[0][0]) if values else ""
        collection_title = section_headings[0][1] if slug in collections else None
        recipes.append({"id": stable, "title": title, "category": category, "collectionTitle": collection_title, "sourceFile": path.name, "sourceSection": title, "introduction": first("pre"), "ingredients": ingredients, "steps": steps, "tips": [clean(v[0]) for v in commands(segment, "tip")], "healthierOptions": [clean(v[0]) for v in commands(segment, "healthierOption")], "sourceHash": hashlib.sha256(segment.encode()).hexdigest()})
    return recipes


def clean_grocery_name(value: str) -> str:
    """Keep the ingredient identity while removing package/measurement wording."""
    name = clean(value)
    name = re.sub(r"^(?:\d+(?:[./]\d+)?\s+)?", "", name)
    name = re.sub(r"^(?:small|medium|large|extra[- ]large)\s+", "", name, flags=re.I)
    name = re.sub(r"^(?:cups?|tablespoons?|teaspoons?|ounces?|oz|pounds?|lbs?|grams?|kilograms?|quarts?|pints?|gallons?|cloves?|sticks?|cans?|jars?|packages?|pkgs?|bags?|bottles?|boxes?|bunches?|heads?)\s+(?:of\s+)?", "", name, flags=re.I)
    name = re.sub(r"^(?:can|jar|package|pkg|bag|bottle|box|container)\s+(?:of\s+)?", "", name, flags=re.I)
    name = name.strip(" ,.-")
    return name[:1].upper() + name[1:] if name else name


def build() -> dict:
    metadata = json.loads(METADATA_PATH.read_text(encoding="utf-8")) if METADATA_PATH.exists() else {}
    recipes, seen_files = [], set()
    for slug, category in index_entries():
        if slug in seen_files:
            raise ValueError(f"duplicate index entry: {slug}")
        seen_files.add(slug)
        recipes.extend(parse_file(slug, category, metadata))
    identities = [r["id"] for r in recipes]
    if len(identities) != len(set(identities)):
        raise ValueError("duplicate stable recipe IDs")
    for recipe in recipes:
        if not recipe["steps"]:
            raise ValueError(f"{recipe['sourceFile']} ({recipe['title']}): no instruction paragraphs were parsed")
        ingredient_ids = {ingredient["id"] for ingredient in recipe["ingredients"]}
        for step in recipe["steps"]:
            unresolved = set(step["ingredientIDs"]) - ingredient_ids
            if unresolved:
                raise ValueError(f"{step['id']}: unknown ingredient IDs: {', '.join(sorted(unresolved))}")
    if THUMBNAIL_MANIFEST_PATH.is_file():
        manifest = json.loads(THUMBNAIL_MANIFEST_PATH.read_text(encoding="utf-8"))
        from thumbnail_support import fingerprint

        for recipe in recipes:
            entry = manifest.get("recipes", {}).get(recipe["id"], {})
            asset_name = f"{recipe['id']}.jpg"
            if (entry.get("asset") == asset_name
                    and entry.get("promptFingerprint") == fingerprint(recipe)
                    and (THUMBNAIL_DIRECTORY / asset_name).is_file()):
                recipe["thumbnailAsset"] = asset_name
    return {"schemaVersion": 1, "source": "Cookbook.tex", "categoryOrder": list(dict.fromkeys(category for _, category in index_entries())), "recipeFileCount": len(seen_files), "recipes": recipes}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="ios/Cookbook/Resources/recipes.json")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        data = build()
        output = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        target = ROOT / args.output
        if args.check:
            if not target.is_file() or target.read_text(encoding="utf-8") != output:
                print(f"Catalog is stale: run make catalog ({args.output})", file=sys.stderr)
                return 1
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(output, encoding="utf-8")
        print(f"{len(data['recipes'])} recipes from {data['recipeFileCount']} source files")
        return 0
    except (OSError, ValueError) as error:
        print(f"catalog error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
