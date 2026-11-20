import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import subagents from "pi-subagents";
import { registerRequiredChildExtensions } from "pi-subagents/required-child-extensions";

export default async function (pi: ExtensionAPI) {
  const file = process.env.NVIM_PI_STATUS;
  const run = process.env.NVIM_PI_RUN;
  const expectedModel = process.env.NVIM_PI_MODEL;
  let sequence = 0;
  if (file && existsSync(file)) {
    const previous = JSON.parse(readFileSync(file, "utf8"));
    if (previous.run === run && Number.isSafeInteger(previous.sequence)) sequence = previous.sequence;
  }
  let activity = "idle";
  let outcome = "unknown";
  let waiting = 0;
  let registration: { dispose(): void } | undefined;

  function publish(ctx: ExtensionContext, model = ctx.model) {
    if (!file || !run) return;
    mkdirSync(dirname(file), { recursive: true, mode: 0o700 });
    const snapshot = {
      version: 1, run, sequence: ++sequence, activity: waiting ? "waiting" : activity,
      outcome, cwd: ctx.cwd, session: ctx.sessionManager.getSessionId(),
      session_file: ctx.sessionManager.getSessionFile(),
      model: model ? `${model.provider}/${model.id}` : "unavailable",
    };
    const temporary = `${file}.${process.pid}.tmp`;
    writeFileSync(temporary, JSON.stringify(snapshot), { mode: 0o600 });
    renameSync(temporary, file);
  }

  pi.on("session_start", (_event, ctx) => {
    activity = "idle";
    waiting = 0;
    registration?.dispose();
    registration = registerRequiredChildExtensions({
      sessionId: ctx.sessionManager.getSessionId(),
      extensions: [{ id: "nvim-issue-model", path: join(dirname(fileURLToPath(import.meta.url)), "child-policy.ts") }],
      requireForAllRunners: true,
    });
    publish(ctx);
  });
  pi.on("agent_start", (_event, ctx) => {
    activity = "working";
    outcome = "unknown";
    publish(ctx);
  });
  pi.on("agent_before_settle", (event, ctx) => {
    outcome = event.outcome;
    publish(ctx);
  });
  pi.on("agent_settled", (event, ctx) => {
    activity = "idle";
    if (event.aborted) outcome = "aborted";
    publish(ctx);
  });
  pi.on("ui_prompt_start", (_event, ctx) => { waiting++; publish(ctx); });
  pi.on("ui_prompt_end", (_event, ctx) => { waiting = Math.max(0, waiting - 1); publish(ctx); });
  pi.on("model_select", (event, ctx) => publish(ctx, event.model));
  pi.on("session_shutdown", (event, ctx) => {
    registration?.dispose();
    registration = undefined;
    if (event.reason === "quit") activity = "exited";
    publish(ctx);
  });

  // Only the foreground, single-child entry point belongs to this UI.
  pi.on("tool_call", (event, ctx) => {
    if (event.toolName !== "subagent" && event.toolName !== "subagent_launch") return;
    const input = event.input as Record<string, unknown>;
    if (event.toolName === "subagent_launch" || typeof input.agent !== "string"
      || input.async !== false || input.workflowScript !== undefined || input.chain !== undefined
      || input.parallel !== undefined || (input.worktree !== undefined && input.worktree !== false)
      || input.machine !== undefined || (input.cwd !== undefined && input.cwd !== ctx.cwd)) {
      return { block: true, reason: "Issue tabs support one foreground subagent per call: set agent, async: false, the current cwd, and an explicit model. No workflow scripts, background jobs, nested launches, or managed worktrees." };
    }
    if (input.model !== expectedModel) {
      return { block: true, reason: `Set model explicitly to ${expectedModel} for this issue's subagent.` };
    }
  });
  const informational = new Set(["subagents-guide", "subagents-doctor", "subagent-cost"]);
  await subagents({
    ...pi,
    registerCommand(name, command) {
      if (informational.has(name)) pi.registerCommand(name, command);
    },
    // The extension's launch/detach shortcuts are for external inspectors.
    registerShortcut() {},
  });
}
