#!/usr/bin/env python3
"""
patch-gguf-template.py — Fix broken/unparseable chat templates on locally
pulled Ollama models. Two unrelated bugs, two unrelated fixes, one script:

1. Mistral GGUFs whose embedded Jinja template raises an exception unless
   roles strictly alternate user/assistant, which breaks a leading system
   message. Fixed with an in-place, same-length byte patch on the raw GGUF
   file (see `patch()` below).

   Usage: python3 patch-gguf-template.py <path-to-model.gguf>

2. Qwen3.5-family GGUFs (e.g. community Bonsai-27B re-uploads) whose embedded
   template is too complex (macros, multi-pass role validation) for Ollama's
   `minja`-based template-to-parser compiler to statically analyze at all —
   it fails outright with "Unable to generate parser for this template"
   before any generation happens. This isn't a byte-level bug to patch; the
   fix is to override the model's Modelfile TEMPLATE with an explicit
   ChatML-style Ollama Go-template (bypassing the broken GGUF template and
   minja's parser-generation step entirely). See `patch_ollama_model()`.

   Usage: python3 patch-gguf-template.py --ollama-model <name>[:<tag>] [--out <new-name>]
   Creates a new Ollama model (default: "<name>-patched") sharing the same
   weight blobs, with a working template. Idempotent: skips creation if the
   target name already exists.

Exit codes:
  0: Success or already patched
  1: Error (file not found, patch failed, etc.)
"""
import argparse
import subprocess
import sys
import os
import shutil
import tempfile

# Known-good ChatML template for Qwen3/Qwen3.5-architecture models, adapted
# from Ollama's own qwen3 template. Written in Ollama's Go-template syntax
# (not Jinja), so it never touches minja's parser-generation path.
QWEN_CHATML_TEMPLATE = '''TEMPLATE """{{- $lastUserIdx := -1 -}}
{{- range $idx, $msg := .Messages -}}
{{- if eq $msg.Role "user" }}{{ $lastUserIdx = $idx }}{{ end -}}
{{- end }}
{{- if or .System .Tools }}<|im_start|>system
{{ if .System }}{{ .System }}

{{ end }}
{{- if .Tools }}# Tools

You may call one or more functions to assist with the user query.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
{{- range .Tools }}
{"type": "function", "function": {{ .Function }}}
{{- end }}
</tools>

For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:
<tool_call>
{"name": <function-name>, "arguments": <args-json-object>}
</tool_call>
{{- end -}}
<|im_end|>
{{ end }}
{{- range $i, $_ := .Messages }}
{{- $last := eq (len (slice $.Messages $i)) 1 -}}
{{- if eq .Role "user" }}<|im_start|>user
{{ .Content }}<|im_end|>
{{ else if eq .Role "assistant" }}<|im_start|>assistant
{{ if (and $.IsThinkSet (and .Thinking (or $last (gt $i $lastUserIdx)))) -}}
<think>{{ .Thinking }}</think>
{{ end -}}
{{ if .Content }}{{ .Content }}{{ end }}
{{- if .ToolCalls }}
{{- range .ToolCalls }}
<tool_call>
{"name": "{{ .Function.Name }}", "arguments": {{ .Function.Arguments }}}
</tool_call>
{{- end }}
{{- end }}{{ if not $last }}<|im_end|>
{{ end }}
{{- else if eq .Role "tool" }}<|im_start|>user
<tool_response>
{{ .Content }}
</tool_response><|im_end|>
{{ end }}
{{- if and (ne .Role "assistant") $last }}<|im_start|>assistant
<think>
{{ end }}
{{- end }}"""

PARAMETER temperature 0.6
PARAMETER top_k 20
PARAMETER top_p 0.95
PARAMETER repeat_penalty 1
PARAMETER stop <|im_start|>
PARAMETER stop <|im_end|>
PARAMETER num_ctx 32768
'''


def patch_ollama_model(model_name: str, out_name: str | None) -> None:
    """Create a template-patched copy of an Ollama model using ChatML.

    Args:
        model_name: Source model name as known to `ollama` (name[:tag])
        out_name: Name for the patched model (default: "<name>-patched")
    """
    out_name = out_name or f"{model_name.split(':')[0].split('/')[-1]}-patched"

    existing = subprocess.run(
        ["ollama", "list"], capture_output=True, text=True, check=True
    ).stdout
    if any(line.split()[0].split(":")[0] == out_name for line in existing.splitlines()[1:] if line.strip()):
        print(f"  ✓ '{out_name}' already exists — nothing to do")
        sys.exit(0)

    modelfile = f"FROM {model_name}\n\n{QWEN_CHATML_TEMPLATE}"

    with tempfile.NamedTemporaryFile("w", suffix=".Modelfile", delete=False) as f:
        f.write(modelfile)
        modelfile_path = f.name

    try:
        print(f"  Creating '{out_name}' from '{model_name}' with ChatML template override...")
        result = subprocess.run(
            ["ollama", "create", out_name, "-f", modelfile_path],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(f"  ✗ ollama create failed:\n{result.stderr}", file=sys.stderr)
            sys.exit(1)
        print(f"  ✓ Created '{out_name}' — use it via: pi --model {out_name} --provider ollama")
        sys.exit(0)
    finally:
        os.unlink(modelfile_path)

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
        print(f"  ✗ File not found: {model_path}", file=sys.stderr)
        sys.exit(1)
    
    if not os.access(model_path, os.R_OK | os.W_OK):
        print(f"  ✗ No read/write permission for: {model_path}", file=sys.stderr)
        sys.exit(1)

    try:
        # Read enough of the file to cover the metadata section
        read_size = 4 * 1024 * 1024  # 4 MB — metadata is always near the start
        with open(model_path, "rb") as f:
            header = f.read(read_size)
    except IOError as e:
        print(f"  ✗ Failed to read {model_path}: {e}", file=sys.stderr)
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
        print("  ✗ ERROR: new template is longer than old — cannot patch in-place", file=sys.stderr)
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
        print(f"  ✗ Failed to create backup: {e}", file=sys.stderr)
        sys.exit(1)

    # Write patch
    try:
        with open(model_path, "r+b") as f:
            f.seek(idx)
            f.write(new_template)
    except IOError as e:
        print(f"  ✗ Failed to write patch: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"  ✓ Chat template patched at offset 0x{idx:x}")
    sys.exit(0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Patch broken chat templates on locally pulled Ollama models."
    )
    parser.add_argument("gguf_path", nargs="?", help="Path to a Mistral .gguf file to byte-patch")
    parser.add_argument(
        "--ollama-model", metavar="NAME[:TAG]",
        help="Ollama model with an unparseable template; create a ChatML-patched copy",
    )
    parser.add_argument(
        "--out", metavar="NAME",
        help="Name for the patched model (with --ollama-model; default: '<name>-patched')",
    )
    args = parser.parse_args()

    if args.ollama_model:
        patch_ollama_model(args.ollama_model, args.out)
    elif args.gguf_path:
        patch(args.gguf_path)
    else:
        parser.print_usage(sys.stderr)
        sys.exit(1)
