"""Emit schema from the historical production repair; omit its top-level data writes."""
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
tokens = re.split(r"(\$[A-Za-z_0-9]*\$|--[^\n]*\n|'(?:[^']|'')*'|;)", source)
statement = ""
tag = None
for token in tokens:
    if re.fullmatch(r"\$[A-Za-z_0-9]*\$", token):
        if tag == token:
            tag = None
        elif tag is None:
            tag = token
    statement += token
    if token == ";" and tag is None:
        clean = re.sub(r"--[^\n]*", "", statement).strip()
        if not re.match(r"(?is)^(insert|update|delete|with)\b", clean):
            sys.stdout.write(statement)
        statement = ""
