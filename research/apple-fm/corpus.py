#!/usr/bin/env python3
"""Generate and validate 500 transparent template variants from 100 authored seeds."""
from collections import Counter
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
CATEGORIES = ("general", "homophone", "mixed", "engineering", "preserve")
TEMPLATES = (
    ("plain", ""),
    ("meeting", "這是會議中的一句話。"),
    ("note", "筆記中記錄了以下內容。"),
    ("message", "我們正在整理這則訊息。"),
    ("review", "以下內容仍在編輯中。"),
)


def generate(seeds):
    output = []
    for seed in seeds:
        for variant, (template_id, prefix) in enumerate(TEMPLATES):
            candidates = [seed["answer"], *seed["distractors"]]
            # Preserve cases test harmful changes to an already correct first candidate.
            # Other cases deliberately rotate positions, not scores from McBopomofo.
            rotation = 0 if seed["category"] == "preserve" else variant % len(candidates)
            candidates = candidates[rotation:] + candidates[:rotation]
            output.append({
                "id": f'{seed["id"]}-{template_id}',
                "seed_id": seed["id"],
                "template_id": template_id,
                "category": seed["category"],
                "context": prefix + seed["context"],
                "candidates": [{"id": i, "text": text} for i, text in enumerate(candidates)],
                "expected_id": candidates.index(seed["answer"]),
                "answer": seed["answer"],
                "provenance": seed["provenance"],
            })
    return output


def validate(cases):
    if len(cases) != 500:
        raise ValueError("Expected exactly 500 cases")
    if Counter(row["category"] for row in cases) != Counter({category: 100 for category in CATEGORIES}):
        raise ValueError("Each of the five categories must contain exactly 100 cases")
    if len({row["id"] for row in cases}) != 500:
        raise ValueError("Case IDs must be unique")
    if len({row["seed_id"] for row in cases}) != 100:
        raise ValueError("Must disclose exactly 100 seed groups")
    if set(Counter(row["seed_id"] for row in cases).values()) != {5}:
        raise ValueError("Each seed must have five variants")
    template_ids = {template_id for template_id, _ in TEMPLATES}
    for seed_id in {row["seed_id"] for row in cases}:
        if {row["template_id"] for row in cases if row["seed_id"] == seed_id} != template_ids:
            raise ValueError("Each seed must contain every template exactly once")
    for row in cases:
        if not isinstance(row["context"], str) or not row["context"] or len(row["context"].encode()) > 1024:
            raise ValueError("Invalid or oversized context")
        if row["template_id"] not in template_ids or not row["provenance"]:
            raise ValueError("Missing template provenance")
        candidates = row["candidates"]
        ids = [candidate["id"] for candidate in candidates]
        texts = [candidate["text"] for candidate in candidates]
        if not 1 <= len(candidates) <= 32 or len(set(ids)) != len(ids) or len(set(texts)) != len(texts):
            raise ValueError("Candidates must be nonempty and unique")
        if any(type(value) is not int for value in ids) or type(row["expected_id"]) is not int:
            raise ValueError("Candidate IDs must be integers")
        if any(not text or len(text.encode()) > 256 for text in texts):
            raise ValueError("Invalid or oversized candidate text")
        correct = [candidate for candidate in candidates if candidate["id"] == row["expected_id"]]
        if len(correct) != 1 or correct[0]["text"] != row["answer"]:
            raise ValueError("Expected answer must match an existing candidate ID")
    return {"cases": len(cases), "seed_groups": 100, "categories": dict(Counter(row["category"] for row in cases))}


def main():
    seeds = json.loads((HERE / "seed-pairs.json").read_text())
    cases = generate(seeds)
    summary = validate(cases)
    (HERE / "corpus-500.json").write_text(json.dumps(cases, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(summary, indent=2))

if __name__ == "__main__":
    main()
