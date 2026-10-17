# Local coding model findings

Tested 2026-10-17 on a GTX 1660 SUPER (6 GB VRAM) with 15 GiB RAM. These were
small local probes, not a comprehensive model benchmark.

| Model            | Local result                                                                                                                                                                                   |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Qwen 3.5 4B Q4   | Fits entirely on GPU at 16K context (3.5 GB loaded). Warm first token: 0.3–0.8 s; about 58 tokens/s. Pi tool use and the C write/compile/run check passed. A harder tested coding task failed. |
| Qwen 3.5 9B Q4   | Partly offloaded to RAM; about 7 tokens/s. No accuracy gain on the probes used.                                                                                                                |
| Qwen2.5 Coder 7B | Starts replying quickly when warm, but missed coding and debugging edge cases.                                                                                                                 |
| Gemma 4 E2B QAT  | Fits on GPU and calls pi tools, but missed a debugging probe and failed the tested coding task.                                                                                                |

**Choice:** `qwen3.5-coding:4b`, derived from `qwen3.5:4b-q4_K_M` by
[`Coding.Modelfile`](Coding.Modelfile). Pi is Neovim's agent and uses this model
by default. `make use-model` refreshes the derived model and preloads it with
`keep_alive=-1`; `ollama ps` confirmed 16K context, 100% GPU, and `Forever`.
This holds about 3.5 GB of VRAM while loaded. The comparison downloads were
removed; the preexisting Ministral model was retained.
