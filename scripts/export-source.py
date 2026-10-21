#!/usr/bin/env python3
"""Export tracked public sources, excluding local additions and private artifacts."""
import importlib.util
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DIRECTORIES = {"Sources", "Resources", "docs", "scripts", "tests", ".github", ".githooks"}
FILES = {"README.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "SUPPORT.md", "SECURITY.md",
         "CHANGELOG.md", "LICENSE", "LICENSE.SonyBridge", "LICENSE.SonyHeadphonesClient",
         "THIRD_PARTY_NOTICES.md", ".gitignore"}


def tracked_names(root):
    result = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=root,
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if result.returncode == 0 and Path(os.fsdecode(result.stdout.strip())).resolve() == root.resolve():
        data = subprocess.check_output(["git", "ls-files", "-z"], cwd=root)
        return [os.fsdecode(name) for name in data.split(b"\0") if name]
    manifest = root / "SOURCE_MANIFEST.txt"
    if manifest.is_file() and not manifest.is_symlink():
        return manifest.read_text().splitlines()
    raise ValueError("Use a Git checkout or an exported archive with SOURCE_MANIFEST.txt")


def export(root, destination, names, omit_images=False):
    if destination.exists():
        raise ValueError("Export destination must not exist")
    spec = importlib.util.spec_from_file_location("privacy_guard", root / "scripts/check-public-privacy.py")
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    selected = []
    for name in sorted(set(names)):
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "\n" in name or "\r" in name or "\\" in name:
            raise ValueError("Unsafe path in source manifest")
        if not path.parts or (path.parts[0] not in DIRECTORIES and name not in FILES):
            continue
        if omit_images and ((path.parent == PurePosixPath("Resources/Devices") and path.suffix.lower() == ".png")
                            or path.parts[:2] == ("docs", "images")):
            continue
        source = root / name
        # Check every component, not just the final file, to reject directory symlinks too.
        if any(candidate.is_symlink() for candidate in [source, *source.parents] if candidate != root and root in candidate.parents):
            raise ValueError(f"Symlink is not allowed in source export: {name}")
        if not source.is_file():
            raise ValueError(f"Tracked source is missing: {name}; stage intended deletions first")
        data = source.read_bytes()
        issues = guard.check(name, data)
        if issues:
            raise ValueError(f"Privacy review required for {name}: {', '.join(issues)}")
        selected.append((name, data, source.stat().st_mode & 0o111))
    destination.mkdir(parents=True)
    for name, data, executable in selected:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o755 if executable else 0o644)
    (destination / "SOURCE_MANIFEST.txt").write_text("".join(name + "\n" for name, _, _ in selected))
    return len(selected)


def main():
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: python3 scripts/export-source.py DESTINATION")
        mode = os.environ.get("OPENSOUND_DEVICE_IMAGES", "bundled")
        if mode not in {"bundled", "none"}:
            raise ValueError("OPENSOUND_DEVICE_IMAGES must be bundled or none")
        count = export(ROOT, Path(sys.argv[1]), tracked_names(ROOT), mode == "none")
        print(f"Exported {count} privacy-checked source files; device images: {mode}")
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Source export blocked: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
