#!/usr/bin/env python3
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
