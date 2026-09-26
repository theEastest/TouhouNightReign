"""Compile a th15 `.decl` ECL dump into a compact Lua chunk table.

The `.decl` text produced by `thecl -d15` is a readable rendering of the
compiled ECL bytecode. Running a text parser at game start would be wasteful and
would put a large tokenizer on the hot path, so this tool lowers every
instruction to a small integer opcode plus resolved operands and writes one Lua
table per subroutine.

Usage:
    python tools/compile_ecl.py <decl_dir> <out.lua> [stage_filter]

The output is a Lua module returning:
    {
      [ "GirlA01" ] = { name = "GirlA01", instructions = { {op, ...}, ... } },
      ...
    }
Each instruction is { op = <name>, a = ..., b = ..., c = ... }.
"""
import io
import os
import re
import sys

# Difficulty branch blocks. `!E` easy, `!N` normal, `!H` hard, `!L` lunatic,
# `!O` overdrive (th15 extra), `!*` ends the block. `!NHL` and similar combine
# several difficulties. The compiler keeps a per-difficulty variant so the
# runtime can pick the right branch instead of hard-coding one.
DIFF_KEYS = {"E": "easy", "N": "normal", "H": "hard", "L": "lunatic", "O": "overdrive"}


def parse_value(token):
    """Convert a literal token to a Python value descriptor."""
    token = token.strip()
    if token.endswith("f"):
        try:
            return ("f", float(token[:-1]))
        except ValueError:
            pass
    try:
        return ("i", int(token))
    except ValueError:
        return ("raw", token)


def split_args(text):
    """Split a comma separated argument list, respecting brackets."""
    args, depth, current = [], 0, ""
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            args.append(current.strip())
            current = ""
        else:
            current += ch
    if current.strip():
        args.append(current.strip())
    # The decl renderer escapes a string operand as \"Name\". Strip the wrapper
    # so the runtime receives a plain name.
    cleaned = []
    for arg in args:
        if len(arg) >= 2 and arg.startswith('\\"') and arg.endswith('\\"'):
            arg = arg[2:-2]
        elif len(arg) >= 2 and arg.startswith('"') and arg.endswith('"'):
            arg = arg[1:-1]
        cleaned.append(arg)
    return cleaned


def compile_file(path):
    """Return { subroutine_name: [ {op, args...}, ... ] } for one decl file."""
    text = io.open(path, encoding="utf-8", errors="replace").read()
    # Strip the header directives and prototypes.
    routines = {}
    # Find "void Name()" ... matching closing brace at column 0.
    pattern = re.compile(r"^void\s+([A-Za-z0-9_]+)\s*\(\s*\)\s*\{", re.M)
    for match in pattern.finditer(text):
        name = match.group(1)
        body_start = match.end()
        # find the matching closing brace: the first "\n}\n" at depth 0
        depth = 1
        i = body_start
        while i < len(text) and depth > 0:
            ch = text[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = text[body_start:i]
        routines[name] = compile_body(body)
    return routines


def compile_body(body):
    """Lower a routine body to a list of instruction tuples."""
    raw_lines = body.split("\n")
    # The decl dump wraps long argument lists across lines. Join a line with the
    # next while the parenthesis or bracket depth is positive, so an instruction
    # is never split in the middle of its argument list.
    lines = []
    pending = ""
    depth = 0
    for raw in raw_lines:
        stripped = raw.strip()
        if pending:
            pending = pending + " " + stripped
        else:
            pending = stripped
        depth += pending.count("(") - pending.count(")")
        depth += pending.count("[") - pending.count("]")
        if depth <= 0:
            lines.append(pending)
            pending = ""
            depth = 0
    if pending:
        lines.append(pending)
    # Non-instruction statements we still want to keep so the runtime can
    # reproduce control flow exactly.
    instructions = []
    # Difficulty values declared by the most recent !E/!N/!H/!LO block, in
    # branch order. An instruction operand written as [-1] or [-1.0f] is a
    # back-reference into this list (-1 = the last branch, -2 = the one before).
    diff_values = []
    pending_diff_key = None
    pending_diff_values = {}

    def flush_diff():
        nonlocal diff_values
        if pending_diff_values:
            ordered = []
            for key in ("E", "N", "H", "LO", "O"):
                if key in pending_diff_values:
                    ordered.append(pending_diff_values[key])
            if ordered:
                diff_values = ordered
        pending_diff_values.clear()

    def resolve_placeholders(operands):
        """Replace [-N] operands with a per-difficulty branch list.

        The runtime picks the entry for the active difficulty, so one compiled
        routine works on every mode. The list is emitted as {"E", "N", ...} in
        branch order (easy, normal, hard, lunatic/overdrive) with missing modes
        filled from the closest lighter branch.
        """
        resolved = []
        for operand in operands:
            match = re.match(r"^\[\s*(-\d+)(\.\d+)?f?\s*\]$", operand)
            if match and diff_values:
                distance = int(match.group(1))
                index = len(diff_values) + distance
                if 0 <= index < len(diff_values):
                    resolved.append({"__branches__": list(diff_values)})
                    continue
            resolved.append(operand)
        return resolved

    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        # Labels are referenced by goto targets.
        label = re.match(r"^([A-Za-z0-9_]+):$", line)
        if label:
            instructions.append(("label", label.group(1)))
            continue
        # Local variable declarations carry no behaviour beyond slot naming.
        if line.startswith("var "):
            instructions.append(("var", line[4:].strip()))
            continue
        # Difficulty branch markers.
        if line.startswith("!"):
            key = line[1:].strip()
            if key == "*":
                flush_diff()
                instructions.append(("diff_end",))
            else:
                pending_diff_key = key
                # A combined marker such as !NHL declares one value for several
                # difficulties at once; it is flushed when the block ends.
            continue
        # Bare timed values inside a difficulty block, e.g. "90;" or "1.5f;".
        bare = re.match(r"^([-\d][\w\.]*)f?;$", line)
        if bare:
            if pending_diff_key:
                # Record the value for each difficulty named in the marker.
                for single in pending_diff_key:
                    if single in ("E", "N", "H", "L", "O"):
                        pending_diff_values["LO" if single == "L" else single] = line[:-1]
                    elif single == "O":
                        pending_diff_values["O"] = line[:-1]
                # !LO means lunatic and overdrive share the value.
                if pending_diff_key == "LO":
                    pending_diff_values["LO"] = line[:-1]
            instructions.append(("value", line[:-1]))
            continue
        # if / unless conditional jumps.
        cond = re.match(r"^(if|unless)\s+(.*?)\s+goto\s+([A-Za-z0-9_]+)\s+@\s+(\d+);$", line)
        if cond:
            instructions.append(("goto_if", cond.group(1), cond.group(2), cond.group(3), int(cond.group(4))))
            continue
        # Unconditional goto.
        uncond = re.match(r"^goto\s+([A-Za-z0-9_]+)\s+@\s+(\d+);$", line)
        if uncond:
            instructions.append(("goto", uncond.group(1), int(uncond.group(2))))
            continue
        # Async / call subroutines: "@Name() async;" or "@Name(args) async;".
        call = re.match(r"^@([A-Za-z0-9_]+)\((.*)\)\s*(async)?;$", line)
        if call:
            instructions.append(("call", call.group(1), bool(call.group(3)), split_args(call.group(2))))
            continue
        # Assignment.
        assign = re.match(r"^([\w\$%\s\[\]]+?)\s*(=|\+=|-=)\s*(.+);$", line)
        if assign:
            instructions.append(("assign", assign.group(1).strip(), assign.group(2), assign.group(3).strip()))
            continue
        # Plain instruction call: name(args);
        call_instr = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\((.*)\);$", line)
        if call_instr:
            operands = resolve_placeholders(split_args(call_instr.group(2)))
            instructions.append(("ins", call_instr.group(1), operands))
            continue
        # Routine return.
        if line == "return;":
            instructions.append(("ret",))
            continue
        # Deferred async: "@Name(args) async N;" waits N frames first.
        deferred = re.match(r"^@([A-Za-z0-9_]+)\((.*)\)\s*async\s+(\d+);$", line)
        if deferred:
            instructions.append(("call_after", deferred.group(1), int(deferred.group(3)), split_args(deferred.group(2))))
            continue
        # Positional branch labels such as "+1: //comment".
        plus_label = re.match(r"^\+(\d+):", line)
        if plus_label:
            instructions.append(("label_offset", int(plus_label.group(1))))
            continue
        instructions.append(("raw", line))
    return instructions


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    decl_dir = sys.argv[1]
    out_path = sys.argv[2]
    stage_filter = sys.argv[3] if len(sys.argv) > 3 else None

    files = sorted(f for f in os.listdir(decl_dir) if f.endswith(".decl"))
    if stage_filter:
        files = [f for f in files if stage_filter in f]

    chunks = {}
    for filename in files:
        routines = compile_file(os.path.join(decl_dir, filename))
        # Routine names repeat across stages (every stage has its own GirlA01),
        # so namespace each entry by its source file to keep them distinct.
        namespace = filename[:-len(".decl")]
        for name, instructions in routines.items():
            chunks["%s.%s" % (namespace, name)] = instructions
            # Also publish the bare name for the first file that defines it, so
            # a single-stage lookup still works without the prefix.
            chunks.setdefault(name, instructions)

    lines = [
        "-- Generated by tools/compile_ecl.py. Do not hand-edit.",
        "-- Source: %s" % decl_dir.replace("\\", "/"),
        "return {",
    ]
    for name in sorted(chunks):
        lines.append('    ["%s"] = {' % name)
        for inst in chunks[name]:
            parts = ['"%s"' % inst[0]]
            for value in inst[1:]:
                if isinstance(value, str):
                    cleaned = value.replace('\\"', '"')
                    cleaned = cleaned.replace("\\", "")
                    cleaned = cleaned.replace('"', '\\"').replace("\n", "\\n")
                    parts.append('"%s"' % cleaned)
                elif isinstance(value, bool):
                    parts.append("true" if value else "false")
                elif isinstance(value, list):
                    rendered = []
                    for item in value:
                        if isinstance(item, dict) and "__branches__" in item:
                            inner = ", ".join('"%s"' % v for v in item["__branches__"])
                            rendered.append("{" + inner + "}")
                            continue
                        token = str(item).replace('\\"', '"')
                        token = token.replace("\\", "")
                        rendered.append('"%s"' % token.replace('"', '\\"'))
                    parts.append("{" + ", ".join(rendered) + "}")
                else:
                    parts.append(str(value))
            lines.append("        {" + ", ".join(parts) + "},")
        lines.append("    },")
    lines.append("}")
    io.open(out_path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    print("wrote %s (%d routines, %d files)" % (out_path, len(chunks), len(files)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
