"""Checks the mod scripts against the game's scripts for name clashes, duplicate locals and reserved words.

Usage: python -I check_scripts.py <unpacked scripts.pbo folder> <DayZSolo src folder>
Unpack DayZ\\Addons\\scripts.pbo first: python -I unpbo.py <scripts.pbo> <out folder>
"""
import re, sys
from pathlib import Path
game, mine = Path(sys.argv[1]), Path(sys.argv[2])
types=set()
for f in game.rglob('*.c'):
    t=f.read_text(errors='replace')
    types.update(re.findall(r'^\s*(?:modded\s+)?(?:class|enum)\s+(\w+)', t, re.M))
    types.update(re.findall(r'^\s*typedef\s+[\w<>, ]+\s+(\w+)\s*;', t, re.M))
TYPES=r'(?:ref\s+)?(?:int|float|bool|string|vector|auto|[A-Z]\w*(?:<[^;()=]*>)?)'
decl=re.compile(r'^\s*'+TYPES+r'\s+(\w+)\s*(?:=|;)'); fe=re.compile(r'foreach\s*\(\s*'+TYPES+r'\s+(\w+)\s*:'); forv=re.compile(r'for\s*\(\s*int\s+(\w+)\s*=')
clash=dup=0
for f in sorted(mine.rglob('*.c')):
    raw=f.read_text(); text=re.sub(r'//.*','',re.sub(r'"(?:\\.|[^"\\])*"','""',raw))
    for m in re.finditer(r'\b(?:ref\s+)?[A-Za-z_]\w*(?:<[^;()=]*?>)?\s+([A-Za-z_]\w*)\s*(?=[;=,)(:])', text):
        ctx=text[m.start():m.end()+1]
        if m.group(1) in types and not re.match(r'(class|enum|modded|extends|new|return|override|protected|static|const|ref)\b', ctx.strip()):
            print('clash:', f.name, ctx.strip()); clash+=1
    depth=0; fn=None; seen={}
    for n,l in enumerate(raw.splitlines(),1):
        code=l.split('//')[0]
        if depth==1 and re.search(r'\w+\s*\(.*\)\s*$', code.strip()) and not code.strip().startswith(('if','for','while')): fn=code.strip(); seen={}
        if depth>=2 and fn:
            for rx in (decl,fe,forv):
                for m in rx.finditer(code):
                    v=m.group(1)
                    if v in seen: print(f'dup: {f.name}:{n} {v}'); dup+=1
                    else: seen[v]=n
        depth+=code.count('{')-code.count('}')
KEYWORDS={'class','enum','typedef','extends','modded','sealed','ref','autoptr','owned','out','inout','notnull','const','static','private','protected','proto','native','volatile','event','external','override','thread','local','new','delete','this','super','null','NULL','true','false','return','if','else','for','foreach','while','do','switch','case','default','break','continue','goto','int','float','bool','string','vector','void','typename','func','auto','Class','reference'}
reserved=0
for f in sorted(mine.rglob('*.c')):
    text=re.sub(r'//.*','',re.sub(r'"(?:\\.|[^"\\])*"','""',f.read_text()))
    for m in re.finditer(r'\b(?:int|float|bool|string|vector|auto|[A-Z]\w*(?:<[^;()=]*?>)?)\s+([A-Za-z_]\w*)\s*(?=[;=,)(:\[])', text):
        if m.group(1) in KEYWORDS:
            print('reserved word used as a name:', f.name, 'line', text[:m.start()].count('\n')+1, '->', m.group(0)); reserved+=1
print('name clashes:', clash, '| duplicate declarations:', dup, '| reserved words:', reserved)


def check_configs(src):
    """Each config's CfgPatches may only require patches from other configs, with no loops between them."""
    patch_re = re.compile(r"class\s+(\w+)\s*\{(?:[^{}]|\{[^{}]*\})*?requiredAddons\[\]\s*=\s*\{([^}]*)\}", re.S)
    owner, needs, problems = {}, {}, []
    for cfg in sorted(Path(src).glob("*/config.cpp")):
        text = cfg.read_text(errors="replace")
        block = re.search(r"class\s+CfgPatches\s*\{(.*?)\n\};", text, re.S)
        if not block:
            continue
        for name, req in patch_re.findall(block.group(1)):
            owner[name] = cfg.parent.name
            needs[name] = re.findall(r'"([^"]+)"', req)
    for name, req in needs.items():
        for r in req:
            if r in owner and owner[r] == owner[name]:
                problems.append(f"{owner[name]}/config.cpp: {name} requires {r} from the same config (circular addon dependency)")
    def visit(name, path):
        if name in path:
            problems.append("addon loop: " + " -> ".join(path[path.index(name):] + [name]))
            return
        for r in needs.get(name, []):
            if r in needs and owner[r] != owner[name]:
                visit(r, path + [name])
    for name in needs:
        visit(name, [])
    for line in sorted(set(problems)):
        print("config:", line)
    print(f"config problems: {len(set(problems))}")


check_configs(mine)
