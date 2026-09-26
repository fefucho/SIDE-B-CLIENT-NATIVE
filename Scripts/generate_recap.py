#!/usr/bin/env python3
"""
Script para generar automáticamente un Fix Report / Recap
de todos los arreglos documentados en FIXES_LOG.md desde el último release.
"""

import subprocess
import re
import sys

def get_last_tag():
    try:
        tag = subprocess.check_output(
            ["git", "describe", "--tags", "--abbrev=0"],
            stderr=subprocess.DEVNULL
        ).decode().strip()
        return tag
    except Exception:
        return None

def extract_fixes_since_tag(last_tag):
    fixes = []
    
    # Si hay un tag anterior, comparamos el diff en documentation/FIXES_LOG.md
    fixes_file = "documentation/FIXES_LOG.md"
    if not os.path.exists(fixes_file):
        fixes_file = "FIXES_LOG.md"

    if last_tag:
        try:
            diff = subprocess.check_output(
                ["git", "diff", f"{last_tag}..HEAD", "--", fixes_file],
                stderr=subprocess.DEVNULL
            ).decode()
            
            # Buscar encabezados de fix agregados (+### [FIX-xxx] o [FEAT-xxx])
            current_fix = None
            for line in diff.split("\n"):
                if line.startswith("+### ["):
                    m = re.match(r"^\+### \[((?:FIX|FEAT)-\d+)\]\s*-\s*(.*)", line)
                    if m:
                        current_fix = {"id": m.group(1), "title": m.group(2).strip(), "details": []}
                        fixes.append(current_fix)
                elif current_fix and (line.startswith("+  - **Problema") or line.startswith("+  1. ")):
                    clean = re.sub(r"^\+\s*", "", line).strip()
                    if clean and len(current_fix["details"]) < 2:
                        current_fix["details"].append(clean)
        except Exception:
            pass

    # Si no se obtuvieron por diff, leemos directamente del archivo
    if not fixes and os.path.exists(fixes_file):
        try:
            with open(fixes_file, "r", encoding="utf-8") as f:
                content = f.read()
            pattern = r"### \[((?:FIX|FEAT)-\d+)\]\s*-\s*([^\n]+)"
            for m in re.finditer(pattern, content):
                fixes.append({"id": m.group(1), "title": m.group(2).strip(), "details": []})
                if len(fixes) >= 5:
                    break
        except Exception:
            pass

    return fixes

def generate_markdown(fixes, version):
    lines = [f"### 🎵 Novedades en Side B v{version}\n"]
    if not fixes:
        lines.append("- Mejoras generales de estabilidad y rendimiento en macOS.")
        lines.append("- Optimizaciones de reproducción de audio y sincronización.")
    else:
        for f in fixes:
            lines.append(f"- **{f['title']}** (`{f['id']}`)")
    return "\n".join(lines)

def main():
    version = sys.argv[1] if len(sys.argv) > 1 else "1.0.x"
    last_tag = get_last_tag()
    fixes = extract_fixes_since_tag(last_tag)
    print(generate_markdown(fixes, version))

if __name__ == "__main__":
    main()
