import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import extension from "../../agents/pi/extension.ts";

export default async function (pi: ExtensionAPI) {
  const handlers = new Map<string, Function[]>();
  const commands = new Set<string>();
  await extension({
    ...pi,
    on(event, handler) {
      const callbacks = handlers.get(event) ?? [];
      callbacks.push(handler);
      handlers.set(event, callbacks);
    },
    registerTool() {},
    registerCommand(name) { commands.add(name); },
    registerShortcut() { throw new Error("Inspector shortcuts must not be registered"); },
  });
  pi.on("session_start", async (event, ctx) => {
    const invoke = async (name: string, value: object = {}) => {
      const callback = handlers.get(name)?.[0];
      assert(callback, `Missing ${name}`);
      return callback(value, ctx);
    };
    const snapshot = () => JSON.parse(readFileSync(process.env.NVIM_PI_STATUS!, "utf8"));
    await invoke("session_start", event);
    assert(commands.has("subagents-guide") && !commands.has("run"));
    assert(ctx.model, "The configured default model must be available");
    const valid = { agent: "reviewer", async: false, model: `${ctx.model.provider}/${ctx.model.id}`, cwd: ctx.cwd };
    const guard = (input: object, toolName = "subagent") => invoke("tool_call", { toolName, input });
    assert.equal(await guard(valid), undefined);
    for (const input of [
      { ...valid, async: undefined }, { ...valid, async: true }, { ...valid, model: "inherit" },
      { ...valid, model: "other/model" }, { ...valid, cwd: "/different/worktree" },
      { ...valid, worktree: true }, { ...valid, machine: "remote" },
      { ...valid, workflowScript: "return spawn()" }, { ...valid, agent: undefined, parallel: [] },
    ]) assert.equal((await guard(input))?.block, true, JSON.stringify(input));
    assert.equal((await guard(valid, "subagent_launch"))?.block, true);
    await invoke("agent_start");
    assert.equal(snapshot().activity, "working");
    await invoke("ui_prompt_start");
    assert.equal(snapshot().activity, "waiting");
    await invoke("ui_prompt_end");
    assert.equal(snapshot().activity, "working");
    await invoke("agent_before_settle", { outcome: "error" });
    await invoke("agent_settled", { aborted: false });
    assert.equal(snapshot().activity, "idle");
    assert.equal(snapshot().outcome, "error");
    await invoke("model_select", { model: { provider: "changed", id: "actual-model" } });
    assert.equal(snapshot().model, "changed/actual-model");
    assert.equal((await guard(valid))?.block, true, "Do not retain the previous session model");
    assert.equal(await guard({ ...valid, model: "changed/actual-model" }), undefined);
    await invoke("session_shutdown", { reason: "reload" });
    assert.notEqual(snapshot().activity, "exited");
    await invoke("session_start", event);
    await invoke("session_shutdown", { reason: "quit" });
    assert.equal(snapshot().activity, "exited");
    writeFileSync(join(dirname(process.env.NVIM_PI_STATUS!), "contract-ok"), "ok");
  });
}
