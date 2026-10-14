#!/usr/bin/env python3
"""Check tracked files and reachable Git history before public publication.

This is a heuristic guard, not a substitute for reviewing screenshots and logs.
Diagnostics identify files and rules without printing the matched private data.
"""
import pathlib
import re
import struct
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
RULES = {
    "personal email": rb"[A-Za-z0-9._%+\-]+@(?:gmail\.com|hotmail\.com|outlook\.com|icloud\.com|psu\.ac\.th)",
    "user home path": rb"/(?:Users|home)/[A-Za-z0-9][A-Za-z0-9 ._\-]*/",
    "Bluetooth address": rb"(?i)(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}",
    "private key": rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    "access token": rb"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})",
}
PRIVATE_DIRS = {"analysis", "tools", "vendor", "github-auth", ".aws", ".ssh", "build", "dist"}
PRIVATE_SUFFIXES = {".ipa", ".jsonl", ".pem", ".key", ".p12", ".mobileprovision"}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def check(name, data):
    issues = [rule for rule, pattern in RULES.items() if re.search(pattern, data)]
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        offset = 8
        while offset + 12 <= len(data):
            length = struct.unpack(">I", data[offset:offset + 4])[0]
            kind = data[offset + 4:offset + 8]
            if kind in {b"tEXt", b"iTXt", b"zTXt", b"eXIf"}:
                issues.append("PNG text/EXIF metadata requires manual review")
            offset += length + 12
    path = pathlib.PurePosixPath(name)
    if PRIVATE_DIRS.intersection(path.parts) or path.suffix.lower() in PRIVATE_SUFFIXES or path.name in {".DS_Store", ".env", "hosts.yml"}:
        issues.append("private artifact path")
    return issues


def main():
    findings = set()
    tracked = git("ls-files", "-z").decode().split("\0")[:-1]
    for name in tracked:
        path = ROOT / name
        if path.is_symlink():
            findings.add((name, "symlink requires manual review"))
        elif path.is_file():
            findings.update((name, rule) for rule in check(name, path.read_bytes()))
    # Git history can expose data even after the working copy has been cleaned.
    # Scan each unique reachable blob once, not just the current checkout.
    objects = git("rev-list", "--objects", "--all").decode().splitlines()
    blobs = 0
    for entry in objects:
        oid, sep, name = entry.partition(" ")
        if not sep or git("cat-file", "-t", oid).strip() != b"blob":
            continue
        blobs += 1
        findings.update((f"history:{name}", rule) for rule in check(name, git("cat-file", "blob", oid)))
    for line in git("log", "--all", "--format=%h%x09%ae%x09%ce").decode().splitlines():
        commit, author, committer = line.split("\t")
        for address in (author, committer):
            if not (address.endswith("@users.noreply.github.com") or address == "noreply@github.com"):
                findings.add((f"commit:{commit}", "author/committer email requires review; use GitHub no-reply"))
    for name, rule in sorted(findings):
        print(f"REVIEW: {name}: {rule}", file=sys.stderr)
    if findings:
        print("Privacy guard blocked publication. Review locally; never paste matched data into an issue.", file=sys.stderr)
        return 1
    print(f"Privacy guard passed: {len(tracked)} tracked files, {blobs} reachable blobs, no flagged metadata or commit emails.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
