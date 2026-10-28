#!/usr/bin/env python3
"""Import or replace one validated Markdown recipe in the generated SQLite database."""
import argparse
import sqlite3
import sys
from pathlib import Path
from recipe_markdown import validate_recipe

SCHEMA = """
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS recipes (
    recipe_id TEXT PRIMARY KEY,
    source_slug TEXT NOT NULL,
    title TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('recipe', 'collection')),
    layout TEXT NOT NULL,
    format_version TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS recipe_blocks (
    recipe_id TEXT NOT NULL REFERENCES recipes(recipe_id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    block_type TEXT NOT NULL,
    text_value TEXT,
    PRIMARY KEY (recipe_id, position)
);
CREATE TABLE IF NOT EXISTS ingredient_rows (
    recipe_id TEXT NOT NULL,
    block_position INTEGER NOT NULL,
    row_position INTEGER NOT NULL,
    quantity TEXT NOT NULL,
    ingredient TEXT NOT NULL,
    PRIMARY KEY (recipe_id, block_position, row_position),
    FOREIGN KEY (recipe_id, block_position) REFERENCES recipe_blocks(recipe_id, position) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS schedule_rows (
    recipe_id TEXT NOT NULL,
    block_position INTEGER NOT NULL,
    row_position INTEGER NOT NULL,
    time TEXT NOT NULL,
    task TEXT NOT NULL,
    PRIMARY KEY (recipe_id, block_position, row_position),
    FOREIGN KEY (recipe_id, block_position) REFERENCES recipe_blocks(recipe_id, position) ON DELETE CASCADE
);
PRAGMA user_version = 1;
"""


def import_recipe(recipe_path: str, db_path: str) -> tuple[str, int, int]:
    recipe = validate_recipe(recipe_path)
    db = Path(db_path)
    db.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(db) as connection:
        current_version = connection.execute("PRAGMA user_version").fetchone()[0]
        if current_version not in (0, 1):
            raise ValueError(f"unsupported SQLite schema version {current_version}; this importer supports versions 0 and 1")
        connection.executescript(SCHEMA)
        connection.execute("DELETE FROM recipes WHERE recipe_id = ?", (recipe.recipe_id,))
        connection.execute(
            "INSERT INTO recipes(recipe_id, source_slug, title, kind, layout, format_version) VALUES (?, ?, ?, ?, ?, ?)",
            (recipe.recipe_id, recipe.path.stem, recipe.title, recipe.kind, recipe.layout, recipe.metadata["format"]),
        )
        ingredient_count = schedule_count = 0
        for position, block in enumerate(recipe.blocks):
            kind = block["type"]
            text_value = block.get("text")
            connection.execute(
                "INSERT INTO recipe_blocks(recipe_id, position, block_type, text_value) VALUES (?, ?, ?, ?)",
                (recipe.recipe_id, position, kind, text_value),
            )
            if kind == "ingredients":
                connection.executemany(
                    "INSERT INTO ingredient_rows(recipe_id, block_position, row_position, quantity, ingredient) VALUES (?, ?, ?, ?, ?)",
                    ((recipe.recipe_id, position, row, quantity, ingredient) for row, (quantity, ingredient) in enumerate(block["rows"])),
                )
                ingredient_count += len(block["rows"])
            elif kind == "schedule":
                connection.executemany(
                    "INSERT INTO schedule_rows(recipe_id, block_position, row_position, time, task) VALUES (?, ?, ?, ?, ?)",
                    ((recipe.recipe_id, position, row, time, task) for row, (time, task) in enumerate(block["rows"])),
                )
                schedule_count += len(block["rows"])
    return recipe.recipe_id, ingredient_count, schedule_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recipe_md")
    parser.add_argument("--database", default="build/recipes.sqlite3", help="database path (default: build/recipes.sqlite3)")
    args = parser.parse_args()
    try:
        recipe_id, ingredients, schedule = import_recipe(args.recipe_md, args.database)
    except (OSError, ValueError, sqlite3.Error) as error:
        print(f"SQLite recipe import error: {error}", file=sys.stderr)
        return 1
    print(f"Imported {recipe_id} into {args.database} ({ingredients} ingredients, {schedule} schedule rows)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
