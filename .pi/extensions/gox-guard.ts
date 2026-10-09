// gox-guard 的 pi 扩展：pi 没有 Claude 的 hooks.json，这里把 pi 事件转成 Claude hook 的
// stdin 形状交给插件的 hooks/secrets.sh，再把它的输出翻译回 pi。扫描逻辑、正则、文案只在脚本里一份。
// 依赖是单向的：脚本不知道 pi 存在，pi 只按 Claude hook 的输入输出约定调用它；约定一旦变化，
// tests/pi/gox-guard.test.mjs 会失败。
//   session_start → secrets.sh SessionStart，缺依赖时提示用户
//   tool_call(bash) → secrets.sh PreToolUse，deny 即 { block: true, reason }
// 不 catch 脚本调用失败：pi 在 tool_call handler 出错时会拦下这次调用，与脚本的 fail-closed 一致。
import { execFile } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const script = resolve(dirname(fileURLToPath(import.meta.url)), "../../plugins/gox-guard/hooks/secrets.sh");

// 与插件 hooks.json 中 PreToolUse 的 timeout 90 一致
const TIMEOUT_MS = 90_000;

export default function goxGuardPiExtension(pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		const message = (await runHook("SessionStart", ""))?.additionalContext;
		if (message && ctx.hasUI) ctx.ui.notify(message, "warning");
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return;
		const input = JSON.stringify({
			hook_event_name: "PreToolUse",
			tool_name: "Bash",
			cwd: ctx.cwd,
			tool_input: { command: event.input.command },
		});
		const out = await runHook("PreToolUse", input);
		if (out?.permissionDecision !== "deny") return;
		return { block: true, reason: out.permissionDecisionReason };
	});
}

interface HookOutput {
	additionalContext?: string;
	permissionDecision?: string;
	permissionDecisionReason?: string;
}

// 脚本退出码恒为 0；无输出表示放行
function runHook(event: string, stdin: string): Promise<HookOutput | undefined> {
	return new Promise((done, fail) => {
		const child = execFile("bash", [script, event], { timeout: TIMEOUT_MS }, (err, stdout) => {
			if (err) return fail(err);
			const text = stdout.trim();
			done(text ? (JSON.parse(text).hookSpecificOutput as HookOutput) : undefined);
		});
		child.stdin?.end(stdin);
	});
}
