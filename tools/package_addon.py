"""Build a checked ZIP from the selected repository's committed addon files."""
from pathlib import Path
import re
import stat
import subprocess
import sys
from tempfile import TemporaryDirectory
from zipfile import ZipFile


repo = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
commit = subprocess.check_output(
    ["git", "-C", repo, "rev-parse", "--verify", "HEAD^{commit}"], text=True
).strip()
dist = Path("dist")
dist.mkdir(exist_ok=True)
with TemporaryDirectory(dir=dist) as temp:
    archive = Path(temp).resolve() / "addon.zip"
    subprocess.run(
        ["git", "-C", repo, "archive", "--format=zip", "-o", archive, commit, "GrudgeLedger/"],
        check=True,
    )
    with ZipFile(archive) as package:
        if bad := package.testzip():
            raise ValueError(f"ZIP integrity check failed for {bad}")
        files = set()
        for entry in package.infolist():
            name = entry.filename
            parts = name.rstrip("/").split("/")
            if parts[0] != "GrudgeLedger" or "\\" in name or ":" in name or stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError(f"Unsafe addon archive entry: {name}")
            if any(not part or part.startswith(".") or part.lower() in {"wtf", "savedvariables"} for part in parts):
                raise ValueError(f"Unexpected addon archive entry: {name}")
            if parts[-1].lower() == "grudgeledger.lua" or name.lower().endswith(".bak"):
                raise ValueError(f"Unexpected addon archive entry: {name}")
            if not entry.is_dir() and entry.file_size:
                files.add(name)
        toc = package.read("GrudgeLedger/GrudgeLedger.toc").decode("utf-8-sig")
        lines = [line.strip() for line in toc.splitlines()]
        versions = [line.removeprefix("## Version:").strip() for line in lines if line.startswith("## Version:")]
        if len(versions) != 1 or not re.fullmatch(r"[0-9][A-Za-z0-9.+-]*", versions[0]):
            raise ValueError("Expected one filename-safe addon version in GrudgeLedger.toc")
        entries = [line.replace("\\", "/") for line in lines if line and not line.startswith("#")]
        if not entries:
            raise ValueError("No files listed in GrudgeLedger.toc")
        for required in ["LICENSE", "CREDITS.txt", *entries]:
            if f"GrudgeLedger/{required}" not in files:
                raise ValueError(f"Missing or empty addon file: {required}")
    target = dist / f"GrudgeLedger-{versions[0]}.zip"
    archive.replace(target)
print(f"Verified {target} ({len(files)} files, commit {commit})")
