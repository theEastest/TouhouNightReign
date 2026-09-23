#!/usr/bin/env python3
"""Extract every boss dialogue from the reference activity7 export into JSON.

The reference export defines dialogue as `boss.dialog.New` card blocks inserted
into a boss class's `cards` array. Inside each block, sentences are emitted by
`boss.dialog.sentence(self, speaker_image, side, text, duration, scale, alpha)`
and are usually wrapped in `if GetGlobal('player_name')=='<character>_player'`
branches, so a single block can hold several character-specific conversations.

This tool writes game/scripts/tnr/stages/dialog_text.json keyed by

    {
      "<legacy boss class>": {
        "dialogues": [
          { "index": 0, "variants": [
              { "character": "reimu", "lines": [
                  { "speaker": "image:...", "side": "left", "text": "...",
                    "duration": 180, "scale": 1, "alpha": 1 }, ... ] } ] }, ... ] } }

Only dialogue that can be recovered verbatim from the export is included; a
sentence whose text cannot be parsed is dropped rather than guessed.

Usage:
    python tools/extract_dialogs.py [path/to/_editor_output.lua]
"""
import io
import json
import os
import re
import sys

DEFAULT_SOURCE = r"E:\gemesmods\stg\_reference_extract_20260827\activity7\_editor_output.lua"
DEFAULT_OUTPUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "game", "scripts", "tnr", "stages", "dialog_text.json",
)

CLASS_RE = re.compile(r'^_editor_class\["([^"]+)"\]=Class\(boss\)')
DIALOG_NEW_RE = re.compile(r'^_tmp_sc=boss\.dialog\.New\(')
CARD_NEW_RE = re.compile(r'^_tmp_sc=boss\.card\.New\(')
INSERT_TMP_RE = re.compile(r'^table\.insert\(_editor_class\["([^"]+)"\]\.cards,_tmp_sc\)')
CHARACTER_RE = re.compile(r"GetGlobal\('player_name'\)=='(?:.*?)_player'")
SENTENCE_RE = re.compile(
    r'boss\.dialog\.sentence\(\s*self\s*,\s*'
    r'"((?:[^"\\]|\\.)*)"\s*,\s*'          # speaker image
    r'"((?:[^"\\]|\\.)*)"\s*,\s*'          # side
    r'"((?:[^"\\]|\\.)*)"'                 # text
    r'(?:\s*,\s*([^,)]+))?'                # duration
    r'(?:\s*,\s*([^,)]+))?'                # scale
    r'(?:\s*,\s*([^,)]+))?'                # alpha
)


def unescape_lua_string(value):
    # The reference strings are single-line literals with no escape sequences
    # in practice; handle the common escapes defensively.
    return (value
            .replace('\\"', '"')
            .replace("\\'", "'")
            .replace('\\\\', '\\')
            .replace('\\n', '\n'))


def to_number(value):
    if value is None:
        return None
    value = value.strip()
    try:
        number = float(value)
    except ValueError:
        return None
    return int(number) if number.is_integer() else number


def main():
    source_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not os.path.isfile(source_path):
        raise SystemExit("reference source not found: %s" % source_path)
    with io.open(source_path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().split("\n")

    result = {}
    current_boss = None
    # State for the block currently being parsed.
    in_dialog_block = False
    in_card_block = False
    block_variants = []
    block_index = 0
    current_variant = None
    pending_sentences = []

    def flush_variant():
        nonlocal current_variant, pending_sentences
        if current_variant is not None and pending_sentences:
            current_variant["lines"] = pending_sentences
            block_variants.append(current_variant)
        current_variant = None
        pending_sentences = []

    def flush_block():
        nonlocal block_variants, block_index, in_dialog_block
        flush_variant()
        if block_variants:
            boss = result.setdefault(current_boss, {"dialogues": []})
            boss["dialogues"].append({"index": block_index, "variants": block_variants})
            block_index += 1
        block_variants = []
        in_dialog_block = False

    for line in lines:
        class_match = CLASS_RE.match(line)
        if class_match:
            if in_dialog_block:
                flush_block()
            current_boss = class_match.group(1)
            block_index = 0
            continue

        if DIALOG_NEW_RE.match(line):
            if in_dialog_block:
                flush_block()
            in_dialog_block = True
            in_card_block = False
            block_variants = []
            current_variant = None
            pending_sentences = []
            continue

        if CARD_NEW_RE.match(line):
            if in_dialog_block:
                flush_block()
            in_card_block = True
            continue

        if INSERT_TMP_RE.match(line):
            if in_dialog_block:
                flush_block()
            in_card_block = False
            continue

        if not in_dialog_block:
            continue

        # A new character-specific variant starts at each player_name check.
        if CHARACTER_RE.search(line):
            flush_variant()
            character_match = re.search(r"player_name'\)=='(.*?)_player'", line)
            character = character_match.group(1) if character_match else "all"
            current_variant = {"character": character, "lines": []}
            continue

        sentence_match = SENTENCE_RE.search(line)
        if sentence_match:
            speaker, side, text, duration, scale, alpha = sentence_match.groups()
            text = unescape_lua_string(text)
            if not text.strip():
                continue
            if current_variant is None:
                # A sentence outside a character branch applies to everyone.
                current_variant = {"character": "all", "lines": []}
            pending_sentences.append({
                "speaker": unescape_lua_string(speaker),
                "side": unescape_lua_string(side),
                "text": text,
                "duration": to_number(duration),
                "scale": to_number(scale),
                "alpha": to_number(alpha),
            })

    if in_dialog_block:
        flush_block()

    # Keep only bosses that actually have dialogue with recoverable text.
    result = {boss: data for boss, data in result.items() if data["dialogues"]}
    for boss in result:
        result[boss]["dialogues"].sort(key=lambda item: item["index"])

    ordered = {boss: result[boss] for boss in sorted(result.keys())}
    with io.open(DEFAULT_OUTPUT, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(ordered, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    total_dialogues = sum(len(d["dialogues"]) for d in ordered.values())
    total_lines = 0
    for boss, data in ordered.items():
        for dialogue in data["dialogues"]:
            for variant in dialogue["variants"]:
                total_lines += len(variant["lines"])
    print("wrote %s" % DEFAULT_OUTPUT)
    print("bosses: %d, dialogue blocks: %d, lines: %d" % (len(ordered), total_dialogues, total_lines))


if __name__ == "__main__":
    main()
