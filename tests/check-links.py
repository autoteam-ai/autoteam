"""检查 Markdown 里的相对链接和锚点（锚点按 GitHub 的规则生成）。"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")


def slug(heading):
    heading = heading.strip().lower()
    heading = re.sub(r"[^\w一-鿿\- ]", "", heading)
    return heading.replace(" ", "-")


bad = 0
files = list(root.glob("*.md")) + list(root.glob("docs/**/*.md")) + list(root.glob("skills/**/*.md"))
for md in files:
    if "assets/templates" in str(md):
        continue
    text = md.read_text(encoding="utf-8")
    for match in re.finditer(r"\]\(([^)\s]+)\)", text):
        link = match.group(1)
        if link.startswith(("http", "mailto:", "mention:")):
            continue
        path, _, anchor = link.partition("#")
        target = (md.parent / path).resolve() if path else md.resolve()
        if not target.exists():
            print(f"{md}: 链接不存在 {link}")
            bad += 1
            continue
        if anchor and target.suffix == ".md":
            heads = [slug(h) for h in re.findall(r"^#+\s+(.*)$", target.read_text(encoding="utf-8"), re.M)]
            if anchor not in heads:
                print(f"{md}: 锚点不存在 {link}")
                bad += 1
sys.exit(1 if bad else 0)
