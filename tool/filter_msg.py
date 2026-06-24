#!/usr/bin/env python3
"""
Filters Git commit messages to remove metadata tags like TAG= and CONV=.

Usage:
    git filter-branch --msg-filter "python3 tool/filter_msg.py" <rev-list>

Example:
    git filter-branch --force --msg-filter "python3 tool/filter_msg.py" origin/main..HEAD
"""
import sys

def main():
    msg = sys.stdin.read()
    lines = msg.splitlines()
    filtered = []
    for line in lines:
        stripped = line.strip()
        # Remove spaces to check if it starts with TAG= or CONV=
        normalized = stripped.replace(" ", "")
        if normalized.startswith("TAG=") or normalized.startswith("CONV="):
            continue
        filtered.append(line)
    
    # Strip trailing empty lines
    while filtered and not filtered[-1].strip():
        filtered.pop()
        
    print("\n".join(filtered))

if __name__ == "__main__":
    main()
