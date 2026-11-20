import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", (event) => {
    if (event.toolName === "subagent" || event.toolName === "subagent_launch") {
      return { block: true, reason: "Managed issue subagents cannot launch nested agents. Return findings to the issue's pi." };
    }
  });
}
