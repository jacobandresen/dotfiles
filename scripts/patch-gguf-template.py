#!/usr/bin/env python3
"""
patch-gguf-template.py — Patch the Jinja chat template embedded in a Mistral
GGUF so that system-role messages are folded into the first user turn instead
of raising an exception.

Usage: python3 patch-gguf-template.py <path-to-model.gguf>

Idempotent: re-running on an already-patched file is a no-op.
A .bak backup is created before the first patch.
"""
import sys, os, shutil, struct

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
    if not os.path.isfile(model_path):
        sys.exit(f"File not found: {model_path}")

    # Read enough of the file to cover the metadata section
    read_size = 4 * 1024 * 1024  # 4 MB — metadata is always near the start
    with open(model_path, "rb") as f:
        header = f.read(read_size)

    # Already patched?
    if PATCH_MARKER in header:
        print("  ✓ Chat template already patched — nothing to do")
        return

    idx = header.find(OLD_TEMPLATE)
    if idx == -1:
        print("  ✓ No Mistral template found — patch not needed for this model")
        return

    # Pad new template to the exact same byte length
    pad = len(OLD_TEMPLATE) - len(NEW_TEMPLATE_BASE)
    if pad < 0:
        sys.exit("ERROR: new template is longer than old — cannot patch in-place")
    new_template = NEW_TEMPLATE_BASE + b" " * pad
    assert len(new_template) == len(OLD_TEMPLATE)

    # Backup before first patch
    backup = model_path + ".bak"
    if not os.path.exists(backup):
        print(f"  Creating backup: {backup}")
        shutil.copy2(model_path, backup)

    # Write patch
    with open(model_path, "r+b") as f:
        f.seek(idx)
        f.write(new_template)

    print(f"  ✓ Chat template patched at offset 0x{idx:x}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} <model.gguf>")
    patch(sys.argv[1])
