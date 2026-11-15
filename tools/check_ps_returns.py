"""Finds a PowerShell trap: functions that return their list as one object (`return , $list`)
used directly in `foreach ($x in Func ...)` or piped (`Func | ...`). Both then see the whole list
as a single item. Assign the result to a variable first (`$items = Func; foreach ($x in $items)`).

Usage: python -I check_ps_returns.py <file.ps1>...   (exit code 1 if anything is found)
"""
import re
import sys

problems = 0
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8-sig").read()
    returners = set()
    for match in re.finditer(r"(?m)^function ([\w-]+)", text):
        body_start = match.end()
        following = re.search(r"(?m)^function ", text[body_start:])
        body = text[body_start:body_start + following.start()] if following else text[body_start:]
        if re.search(r"return\s*,\s", body):
            returners.add(match.group(1))
    for name in sorted(returners):
        patterns = [
            r"foreach\s*\(\s*\$\w+\s+in\s+" + re.escape(name) + r"\b",
            r"(?<![\w$-])" + re.escape(name) + r"\b[^\n|()]*\|\s*(ForEach-Object|Where-Object|Sort-Object|Select-Object)",
        ]
        for pattern in patterns:
            for hit in re.finditer(pattern, text):
                line = text[:hit.start()].count("\n") + 1
                print(f"{path}:{line}: '{name}' returns its list as one object; assign it to a variable before looping or piping")
                problems += 1
print(f"list-return problems: {problems}")
sys.exit(1 if problems else 0)
