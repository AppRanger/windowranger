#!/bin/zsh

set -euo pipefail

repository_root="${0:A:h:h}"
requirements="$repository_root/config/dmg-requirements.txt"
tool_root="${WINDOWRANGER_DMG_TOOL_ROOT:-$repository_root/.build/dmg-tools}"
python_command="${WINDOWRANGER_DMG_PYTHON:-}"
dmgbuild="$tool_root/bin/dmgbuild"

[[ -f "$requirements" ]] || { print -u2 "Missing DMG requirements: $requirements"; exit 1; }

if [[ -z "$python_command" ]]; then
    for candidate in \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        "$(command -v python3 || true)"
    do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        if "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
            python_command="$candidate"
            break
        fi
    done
fi

[[ -n "$python_command" && -x "$python_command" ]] || {
    print -u2 "Python 3.10 or newer is required to install the DMG tools"
    exit 1
}

"$python_command" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' || {
    print -u2 "Python 3.10 or newer is required: $($python_command --version 2>&1)"
    exit 1
}

if [[ -x "$dmgbuild" ]]; then
    print "DMG tools already installed: $dmgbuild"
    "$tool_root/bin/python" -c \
        'import importlib.metadata; print("dmgbuild", importlib.metadata.version("dmgbuild"))'
    exit 0
fi

/bin/mkdir -p "${tool_root:h}"
"$python_command" -m venv "$tool_root"
"$tool_root/bin/python" -m pip install \
    --disable-pip-version-check \
    --require-hashes \
    --requirement "$requirements"

print "DMG tools installed: $dmgbuild"
"$tool_root/bin/python" -c \
    'import importlib.metadata; print("dmgbuild", importlib.metadata.version("dmgbuild"))'
