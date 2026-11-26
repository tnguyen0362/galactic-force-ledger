# Sync authoritative Battlefield/*.luau -> test/*.luau with CLI-compatible require rewriting.
# Test copies are GENERATED - never edit them directly.
import re, pathlib

src = pathlib.Path(__file__).parent / "Battlefield"
dst = pathlib.Path(__file__).parent / "test"
dst.mkdir(exist_ok=True)

for f in src.glob("*.luau"):
    text = f.read_text(encoding="utf-8")
    # Roblox instance-path requires -> CLI relative requires
    text = re.sub(r'require\(script\.Parent\.(\w+)\)', r'require("./\1")', text)
    (dst / f.name).write_text(text, encoding="utf-8")
    print("synced", f.name)
print("done")
