#!/usr/bin/env python3
"""
patch-gguf-template.py — Patch the Jinja chat template embedded in a Mistral
GGUF so that system-role messages are folded into the first user turn instead
of raising an exception.

Usage: python3 patch-gguf-template.py <path-to-model.gguf>

Idempotent: re-running on an already-patched file is a no-op.
A .bak backup is created before the first patch.

Exit codes:
  0: Success or already patched
  1: Error (file not found, patch failed, etc.)
"""
import sys
import os
import shutil

PATCH_MARKER = b"{% set ns = namespace(sys='')"

OLD_TEMPLATE = (
    b"{{ bos_token }}"
    b"{% for message in messages %}"
    b"{% if (message['role'] == 'user') != (loop.index0 % 2 == 0) %}"
    b"{{ raise_exception('Conversation roles must alternate user/assistant/user/assistant/...') }}"
    b"{% endif %}"
    b"{% if message['role'] == 'user' %}"
    b"{{ '[INST] ' + message['content'] + ' [/INST]' }}"
    b"{% elif message['role'] == 'assistant' %}"
    b"{{ message['content'] + eos_token}}"
    b"{% else %}"
    b"{{ raise_exception('Only user and assistant roles are supported!') }}"
    b"{% endif %}"
    b"{% endfor %}"
)

# Replacement: folds system messages into the first user turn.
# Padded with trailing spaces to keep byte length identical (in-place patch).
NEW_TEMPLATE_BASE = (
    b"{{ bos_token }}"
    b"{% set ns = namespace(sys='') %}"
    b"{% for message in messages %}"
    b"{% if message['role'] == 'system' %}"
    b"{% set ns.sys = message['content'] + '\\n\\n' %}"
    b"{% elif message['role'] == 'user' %}"
    b"{% if loop.first and ns.sys %}"
    b"{{ '[INST] ' + ns.sys + message['content'] + ' [/INST]' }}"
    b"{% else %}"
    b"{{ '[INST] ' + message['content'] + ' [/INST]' }}"
    b"{% endif %}"
    b"{% elif message['role'] == 'assistant' %}"
    b"{{ message['content'] + eos_token}}"
    b"{% endif %}"
    b"{% endfor %}"
)


def patch(model_path: str) -> None:
    """Patch the GGUF chat template to handle system-role messages.
    
    Args:
        model_path: Path to the GGUF model file
        
    Raises:
        SystemExit: On errors (file not found, patch failure, etc.)
    """
    # Validate file exists and is readable
    if not os.path.isfile(model_path):
        print(f"  ✗ File not found: {model_path}" >&2)
        sys.exit(1)
    
    if not os.access(model_path, os.R_OK | os.W_OK):
        print(f"  ✗ No read/write permission for: {model_path}" >&2)
        sys.exit(1)

    try:
        # Read enough of the file to cover the metadata section
        read_size = 4 * 1024 * 1024  # 4 MB — metadata is always near the start
        with open(model_path, "rb") as f:
            header = f.read(read_size)
    except IOError as e:
        print(f"  ✗ Failed to read {model_path}: {e}" >&2)
        sys.exit(1)

    # Already patched?
    if PATCH_MARKER in header:
        print("  ✓ Chat template already patched — nothing to do")
        sys.exit(0)

    idx = header.find(OLD_TEMPLATE)
    if idx == -1:
        print("  ✓ No Mistral template found — patch not needed for this model")
        sys.exit(0)

    # Pad new template to the exact same byte length
    pad = len(OLD_TEMPLATE) - len(NEW_TEMPLATE_BASE)
    if pad < 0:
        print("  ✗ ERROR: new template is longer than old — cannot patch in-place" >&2)
        sys.exit(1)
    new_template = NEW_TEMPLATE_BASE + b" " * pad
    assert len(new_template) == len(OLD_TEMPLATE), "Template length mismatch"

    # Backup before first patch
    backup = model_path + ".bak"
    try:
        if not os.path.exists(backup):
            print(f"  Creating backup: {backup}")
            shutil.copy2(model_path, backup)
    except IOError as e:
        print(f"  ✗ Failed to create backup: {e}" >&2)
        sys.exit(1)

    # Write patch
    try:
        with open(model_path, "r+b") as f:
            f.seek(idx)
            f.write(new_template)
    except IOError as e:
        print(f"  ✗ Failed to write patch: {e}" >&2)
        sys.exit(1)

    print(f"  ✓ Chat template patched at offset 0x{idx:x}")
    sys.exit(0)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <model.gguf>" >&2)
        sys.exit(1)
    patch(sys.argv[1])
