#!/usr/bin/env python3
"""Find and display the largest files on the filesystem with deletion suggestions."""

import os
import sys
import stat
import argparse
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional
import shutil

# Optional rich for pretty output
try:
    from rich.console import Console
    from rich.table import Table
    from rich import box
    HAS_RICH = True
except ImportError:
    HAS_RICH = False


CATEGORIES = {
    "Video":     {".mp4", ".mkv", ".avi", ".mov", ".wmv", ".flv", ".webm", ".m4v", ".ts", ".vob"},
    "Audio":     {".mp3", ".flac", ".wav", ".aac", ".ogg", ".m4a", ".wma", ".opus"},
    "Image":     {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp", ".heic", ".raw", ".cr2", ".nef"},
    "Archive":   {".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar", ".zst", ".tgz", ".tbz2", ".tbz"},
    "Disk Image":{".iso", ".img", ".vmdk", ".vdi", ".qcow2", ".dmg"},
    "Document":  {".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".odt", ".ods"},
    "Code":      {".py", ".js", ".ts", ".go", ".rs", ".c", ".cpp", ".h", ".java", ".rb", ".sh"},
    "Database":  {".db", ".sqlite", ".sqlite3", ".sql"},
    "Package":   {".deb", ".rpm", ".pkg", ".apk", ".msi", ".exe"},
    "Container": {".tar"},  # docker save output — also matched by Archive, but we check suffix combos below
    "Log":       {".log"},
    "Cache":     {".cache"},
    "Backup":    {".bak", ".old", ".orig", ".backup"},
}

# Paths whose contents are usually safe to delete
DELETABLE_PATH_PATTERNS = [
    "/.cache/",
    "/tmp/",
    "/var/tmp/",
    "/var/cache/",
    "/.local/share/Trash/",
    "/__pycache__/",
    "/node_modules/",
    "/.npm/_cacache/",
    "/.cargo/registry/cache/",
    "/go/pkg/mod/cache/",
    "/.gradle/caches/",
    "/.m2/repository/",
    "/.thumbnails/",
    "/thumbnails/",
]

DELETABLE_EXTENSIONS = {".log", ".bak", ".old", ".orig", ".backup", ".cache", ".pyc", ".pyo"}

DELETABLE_NAMES = {
    "core", "core.gz", ".DS_Store", "Thumbs.db", "desktop.ini",
    "npm-debug.log", "yarn-error.log",
}


def categorize(path: str, ext: str) -> str:
    ext_lower = ext.lower()
    for cat, exts in CATEGORIES.items():
        if ext_lower in exts:
            return cat
    # Guess from path hints
    p = path.lower()
    if "/node_modules/" in p:
        return "Package"
    if "/__pycache__/" in p or ".pyc" in p:
        return "Cache"
    if "/.cache/" in p or "/cache/" in p:
        return "Cache"
    if "/log/" in p or "/logs/" in p:
        return "Log"
    if ext_lower in {".so", ".dylib", ".dll", ".a"}:
        return "Library"
    if ext_lower in {".bin", ""}:
        return "Binary"
    return "Other"


def is_deletable(path: str, ext: str, name: str) -> tuple[bool, str]:
    p = path.lower()
    for pattern in DELETABLE_PATH_PATTERNS:
        if pattern.lower() in p:
            return True, f"in {pattern.strip('/')}"
    if ext.lower() in DELETABLE_EXTENSIONS:
        return True, f"{ext} file"
    if name.lower() in DELETABLE_NAMES:
        return True, "temp/junk file"
    return False, ""


@dataclass
class FileEntry:
    path: str
    size: int
    category: str
    deletable: bool
    delete_reason: str


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PB"


def scan(roots: list[str], skip_mounts: bool, min_size: int) -> list[FileEntry]:
    seen_inodes: set[int] = set()
    entries: list[FileEntry] = []
    root_dev = {r: os.stat(r).st_dev for r in roots}

    def should_skip(path: str, dev: int) -> bool:
        if skip_mounts:
            try:
                if os.stat(path).st_dev != dev:
                    return True
            except OSError:
                return True
        return False

    for root in roots:
        dev = root_dev[root]
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False, onerror=lambda e: None):
            # Prune mount points when requested
            if skip_mounts:
                try:
                    dir_dev = os.stat(dirpath).st_dev
                except OSError:
                    dirnames.clear()
                    continue
                if dir_dev != dev:
                    dirnames.clear()
                    continue
            # Skip proc/sys early
            if dirpath in ("/proc", "/sys", "/dev"):
                dirnames.clear()
                continue

            for fname in filenames:
                fpath = os.path.join(dirpath, fname)
                try:
                    st = os.lstat(fpath)
                except OSError:
                    continue
                if not stat.S_ISREG(st.st_mode):
                    continue
                if st.st_size < min_size:
                    continue
                # Skip hard-link duplicates
                inode_key = (st.st_dev, st.st_ino)
                if inode_key in seen_inodes:
                    continue
                seen_inodes.add(inode_key)

                ext = Path(fname).suffix
                cat = categorize(fpath, ext)
                deletable, reason = is_deletable(fpath, ext, fname)
                entries.append(FileEntry(fpath, st.st_size, cat, deletable, reason))

    entries.sort(key=lambda e: e.size, reverse=True)
    return entries


def print_table_rich(entries: list[FileEntry], top_n: int) -> None:
    console = Console()
    table = Table(
        title=f"Top {min(top_n, len(entries))} Largest Files",
        box=box.ROUNDED,
        show_lines=False,
        header_style="bold cyan",
    )
    table.add_column("#", justify="right", style="dim", width=4)
    table.add_column("Size", justify="right", width=10)
    table.add_column("Category", width=12)
    table.add_column("Del?", justify="center", width=5)
    table.add_column("Reason", width=22)
    table.add_column("Path")

    for i, e in enumerate(entries[:top_n], 1):
        del_mark = "[red]✗[/red]" if e.deletable else ""
        row_style = "red" if e.deletable else ""
        table.add_row(
            str(i),
            human_size(e.size),
            e.category,
            del_mark,
            e.delete_reason,
            e.path,
            style=row_style,
        )
    console.print(table)

    total = sum(e.size for e in entries[:top_n])
    deletable = [e for e in entries[:top_n] if e.deletable]
    deletable_size = sum(e.size for e in deletable)
    console.print(f"\n[bold]Total shown:[/bold] {human_size(total)}  "
                  f"[bold]Flagged deletable:[/bold] [red]{len(deletable)} files "
                  f"({human_size(deletable_size)})[/red]")


def print_table_plain(entries: list[FileEntry], top_n: int) -> None:
    col_widths = (4, 10, 12, 5, 22)
    header = f"{'#':>4}  {'Size':>10}  {'Category':<12}  {'Del?':^5}  {'Reason':<22}  Path"
    sep = "-" * min(shutil.get_terminal_size().columns, 120)
    print(f"\nTop {min(top_n, len(entries))} Largest Files")
    print(sep)
    print(header)
    print(sep)
    for i, e in enumerate(entries[:top_n], 1):
        del_mark = "  *  " if e.deletable else "     "
        print(f"{i:>4}  {human_size(e.size):>10}  {e.category:<12}  {del_mark}  {e.delete_reason:<22}  {e.path}")
    print(sep)
    total = sum(e.size for e in entries[:top_n])
    deletable_size = sum(e.size for e in entries[:top_n] if e.deletable)
    n_del = sum(1 for e in entries[:top_n] if e.deletable)
    print(f"Total shown: {human_size(total)}  |  Flagged deletable: {n_del} files ({human_size(deletable_size)})")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Find the largest files on the filesystem and flag ones safe to delete."
    )
    parser.add_argument(
        "roots", nargs="*", default=["/"],
        help="Root paths to scan (default: /)"
    )
    parser.add_argument(
        "-n", "--top", type=int, default=100,
        help="Number of files to show (default: 100)"
    )
    parser.add_argument(
        "--min-size", type=int, default=1024 * 1024,
        help="Minimum file size in bytes to consider (default: 1 MB)"
    )
    parser.add_argument(
        "--no-skip-mounts", action="store_true",
        help="Cross filesystem boundaries (default: stay on the same device per root)"
    )
    parser.add_argument(
        "--plain", action="store_true",
        help="Plain text output (no rich formatting)"
    )
    args = parser.parse_args()

    skip_mounts = not args.no_skip_mounts

    print(f"Scanning {', '.join(args.roots)} (min size: {human_size(args.min_size)}) ...", file=sys.stderr)
    entries = scan(args.roots, skip_mounts, args.min_size)
    print(f"Found {len(entries):,} files above threshold.", file=sys.stderr)

    if not entries:
        print("No files found.")
        return

    if HAS_RICH and not args.plain:
        print_table_rich(entries, args.top)
    else:
        print_table_plain(entries, args.top)


if __name__ == "__main__":
    main()
