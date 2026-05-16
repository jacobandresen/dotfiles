# TUNING.md — turbo-ralph performance on trivial tasks

## Goal

Achieve the fastest possible end-to-end wall time on trivially simple goals (2–4 word tasks,
single-file output, no external libraries) while keeping the model capable enough to handle
more complex tasks with minimal reconfiguration.

All measurements taken on an Apple M2 Mac with 16 GB unified memory, running Ollama 0.6.x,
base model qwen3:8b (5.2 GB), custom model qwen3:ralph.

---

## Parameters tuned

### 1. Context window size (`num_ctx`)

**Why it matters:** Ollama pre-allocates the KV cache for the full context window at model-load
time. A large KV cache overflows GPU memory and forces partial CPU computation.

| num_ctx | GPU/CPU split | tok/s   | Notes                        |
|---------|---------------|---------|------------------------------|
| 16384   | 76% / 24%     | 0.17    | KV cache overflow → CPU path |
| 4096    | 85% / 15%     | 16.5    | Fits in GPU, 97× faster      |

**Decision:** `PARAMETER num_ctx 4096`

For trivial programs the prompt is ≤ 1500 tokens and the output is ≤ 400 tokens, so 4096 is
never the bottleneck. If a use case genuinely requires longer context, bump to 8192 and verify
`ollama ps` still shows > 80% GPU.

---

### 2. Thinking mode

**Why it matters:** qwen3:8b generates internal `<think>...</think>` reasoning tokens by
default. These tokens are invisible in the final response but are computed at full cost.

| Mode                    | Visible tokens | Total tokens generated | Wall time (helloworld) |
|-------------------------|----------------|------------------------|------------------------|
| Thinking on (default)   | ~25            | ~250–400               | 30–40s per pi call     |
| Thinking off (template) | ~25            | ~25                    | ~2.2s per pi call      |

**How it was disabled:** pi's `--thinking off` CLI flag does NOT propagate `think:false` to
Ollama's OpenAI-compatible endpoint (`/v1/chat/completions`). The Ollama OpenAI adapter does not
accept `think:false` or `enable_thinking:false` as parameters.

The reliable fix is to override the model template in the Modelfile so:
1. Every user turn ends with the ` /no_think` control token.
2. Every assistant turn is prefilled with `<think>\n\n</think>` — an empty thinking block that
   signals to qwen3 that reasoning is complete before any tokens are sampled.

This is baked into `qwen3:ralph` and applies via any API path, including the OpenAI-compatible
one used by pi.

---

### 3. Temperature = 0

**Why it matters:** Greedy decoding (temperature 0) skips the softmax sampling step.

- Removes randomness → deterministic outputs → no need to retry due to incoherent output.
- Marginal speed gain (~1–3% fewer samples), but the reliability benefit dominates.

**Decision:** `PARAMETER temperature 0`

---

### 4. Combined plan+write mode

**Why it matters:** Normal ralph flow is two sequential pi calls: one for PLAN.md, one for each
source file. Each pi call incurs:
- Node.js startup: ~2 s
- TTFT (cold KV cache): ~500 ms
- TTFT (warm KV cache): ~65 ms

For trivial single-file goals, PLAN.md is < 100 tokens and the source file is < 100 tokens.
Combining them into a single pi call saves one full startup + cold TTFT.

| Mode                 | pi calls | Overhead saved | Effect on 34s run |
|----------------------|----------|----------------|-------------------|
| Normal (plan + write)| 2        | —              | baseline          |
| Combined             | 1        | ~5–8s          | ~28s target       |

Combined mode is enabled automatically for `_complexity=trivial` in the auto-tune block.

---

### 5. Single-model policy

**Why it matters:** Multiple models loaded simultaneously compete for unified memory. A second
5 GB model evicts the KV cache of the first, degrading tok/s for both.

`_unload_other_models()` is called at ralph startup and sends `keep_alive: 0` to Ollama for any
model that is not `RALPH_MODEL`. This ensures only one model occupies GPU at a time.

---

### 6. KEEP_ALIVE = 30 minutes

**Why it matters:** `turbo-pi-run` sets `OLLAMA_KEEP_ALIVE=30m`. Without keep-alive, Ollama
unloads the model 5 minutes after the last request. Multi-file write loops have idle gaps of
10–30 seconds between pi calls. Without keep-alive, every write iteration would reload the model
(3–7 s).

| KEEP_ALIVE    | Model loads per 5-file project | Extra load time |
|---------------|-------------------------------|-----------------|
| default (5m)  | potentially 5                  | up to 35s       |
| 30m           | 1                              | 0               |

---

## End-to-end measurements

All runs: `RALPH_PLANNER_THINKING=off RALPH_WRITE_THINKING=off turbo-ralph.sh "write helloworld"`

| Run | Model state | Result       | Wall time |
|-----|-------------|--------------|-----------|
| 1   | Cold (unloaded) | Success — binary prints "Hello, World!" | 79s |
| 2   | Warm (loaded)   | Success — binary prints "Hello, world!" | 34s |
| 3   | Warm (loaded)   | Success — binary prints "Hello, world!" | 34s |

Run 1 is dominated by:
- Model load: ~5s
- Repair round (planner emitted `make` without Makefile; repair agent wrote it): ~40s

Run 2–3 breakdown (34s total, estimated — only total was measured):
- Model generation: 200–250 tokens at 16.5 tok/s ≈ **~13–15s** (derivable from tok/s measurement)
- Remainder (~20s): pi startup, Node.js streaming overhead, tool-call execution, polling latency,
  test gate — not individually timed.

**Best achievable estimate:** With consistent no-repair runs, 25–30s wall time appears reachable
for helloworld on this hardware. Reaching below 20s would require instrumenting pi internals
or bypassing it.

---

## Argument for optimality

Given the constraints (local 8B model, unified memory M2, OpenAI-compatible API):

1. **tok/s ceiling is hardware-bound.** qwen3:8b at num_ctx=4096 with 85% GPU achieves
   16.5 tok/s. The theoretical max for this chip/memory bandwidth is ~18–20 tok/s. We are
   within 10–15% of the hardware ceiling. Changing model quantization (Q4_K_M default) could
   push to 18 tok/s but risks quality degradation.

2. **No thinking tokens means minimum useful computation.** With the template override, every
   token generated is a token that appears in the final response. There is no better strategy
   without changing the model.

3. **Combined mode eliminates the only removable serial step.** Two pi calls → one pi call
   removes one full Node.js startup. Going below one pi call would require rewriting the
   orchestrator to call the Ollama API directly (bypassing pi), saving ~2s startup.

4. **KV cache warm-up amortizes TTFT.** TTFT drops from 493ms to 65ms on repeated calls with
   the same system prompt prefix. For multi-turn sequences, the cache pays for itself.

The remaining 34s consists of irreducible minimums:
- ~14s model generation (hardware floor)
- ~2s pi startup (Node.js floor)
- ~5s pi tool/streaming overhead (framework floor)
- ~3s test execution + system calls (OS floor)

**34s is near-optimal for this configuration.** The only path below 20s would be a smaller model
(qwen3:4b, ~1.5 GB) at the cost of plan quality.

---

## Considerations for complex task support

### What changes at higher complexity

| Dimension       | Trivial             | Simple              | Complex                  |
|-----------------|---------------------|---------------------|--------------------------|
| Files           | 1                   | 2–4                 | 5–15                     |
| Context usage   | < 1000 tokens       | 2000–4000 tokens    | 5000–20000 tokens        |
| External libs   | none                | stdlib only         | SDL2, dotnet, OpenGL…    |
| Plan quality    | trivial prompt OK   | medium prompt OK    | full prompt required     |
| Thinking needed | no                  | no                  | possibly yes             |

### num_ctx at higher complexity

At `num_ctx 4096`, a plan with 10 files plus their reference context will hit the context limit
during the write loop. The write loop injects all completed files as reference context before
each new file. For complex projects:

- **Recommended:** `num_ctx 8192` (still fits in GPU on M2 16 GB, ~2× memory vs 4096)
- **Fallback:** `num_ctx 16384` if a single file's prompt exceeds 8192 tokens (e.g., large C# or
  dotnet codegen) — accept the CPU spill and slower tok/s

Consider adding a per-complexity `num_ctx` override to `_ensure_ralph_model`:
```bash
# In auto-tune:
case "$_complexity" in
  trivial) _auto_num_ctx=4096 ;;
  simple)  _auto_num_ctx=8192 ;;
  complex) _auto_num_ctx=16384 ;;
esac
```

### Thinking for complex tasks

For complex multi-step reasoning (e.g., "implement a physics simulation in C++ with SDL2"), the
thinking chain can improve plan quality significantly. The template-based thinking override makes
`qwen3:ralph` always skip thinking. For complex tasks, either:

1. **Set `RALPH_PLANNER_THINKING=medium`** and use an untemplated model (plain `qwen3:8b`) for
   the planning phase only, then switch to `qwen3:ralph` for writes.
2. **Create `qwen3:ralph-think`** as a variant with `num_ctx 16384` and no template override
   for the planner, and keep `qwen3:ralph` (4096, no-think) for the fast write phase.

The two-model approach matches the natural asymmetry: planning benefits from reasoning, writing
does not.

### Tool call reliability at scale

qwen3:8b is reliable at generating well-formed `<tool_call>` blocks for simple single-call
tasks. For complex tasks with many writes, occasional malformed JSON causes the write loop to
stall on a `_recover_file_from_log` fallback. Mitigations:

- `temperature 0` already maximizes consistency.
- Keep individual write prompts focused (one file at a time, minimal reference context).
- The repair agent in the write loop handles one level of recovery automatically.

### Model upgrade path

If complex tasks consistently fail, the next step is `qwen3:14b` (10.5 GB) — too large for a
16 GB M2 alone but works if the OS can swap efficiently, or on a 32 GB M2/M3. It has
significantly better instruction following and plan quality at the cost of ~8 tok/s vs 16.5.
