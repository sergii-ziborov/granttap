import { mkdtempSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { createConnection } from "node:net";

const binary = process.env.GRANTTAP_TEST_ENGINE_BINARY;
if (!binary) throw new Error("GRANTTAP_TEST_ENGINE_BINARY is required");
const root = mkdtempSync(join(tmpdir(), "granttap-desktop-ui-"));
const socket = join(root, "engine.sock");
const workspace = join(root, "workspace");
mkdirSync(workspace);
const engine = spawn(binary, [], {
  env: { ...process.env, GRANTTAP_ENGINE_SOCKET: socket },
  stdio: "ignore",
});

function cleanup() {
  engine.kill("SIGTERM");
  rmSync(root, { recursive: true, force: true });
}
process.on("SIGINT", () => { cleanup(); process.exit(0); });
process.on("SIGTERM", () => { cleanup(); process.exit(0); });
process.on("exit", cleanup);

for (let attempt = 0; attempt < 200 && !existsSync(socket); attempt++) {
  if (engine.exitCode !== null) throw new Error("Engine stopped before socket was ready");
  await new Promise((resolve) => setTimeout(resolve, 10));
}
if (!existsSync(socket)) throw new Error("Engine socket did not appear");

async function send(operation, input, id) {
  const body = Buffer.from(JSON.stringify({
    protocol_version: 1, request_id: id, operation, input,
  }));
  const frame = Buffer.alloc(4 + body.length);
  frame.writeUInt32BE(body.length, 0);
  body.copy(frame, 4);
  const response = await new Promise((resolve, reject) => {
    const client = createConnection(socket);
    let buffer = Buffer.alloc(0);
    client.once("connect", () => client.write(frame));
    client.on("data", (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      if (buffer.length < 4 || buffer.length < 4 + buffer.readUInt32BE(0)) return;
      client.end();
      resolve(JSON.parse(buffer.subarray(4, 4 + buffer.readUInt32BE(0)).toString()));
    });
    client.once("error", reject);
  });
  if (response.status !== "ok") {
    throw new Error(`${operation} failed: ${response.error?.code ?? "unknown"}`);
  }
}

const project = "desktop-ui-project";
await send("project.upsert_binding", {
  project: { project_id: project, name: "GrantTap UI Test", created_at: 1 },
  binding: { binding_id: "mac-repository", project_id: project,
    endpoint_id: "test-mac", repository_id: "granttap-test-repository",
    local_root: workspace, role: "primary", last_seen_at: 1 },
}, "binding");
await send("policy.apply", {
  expected_revision: 0,
  policy: { project_id: project, revision: 1,
    enforcement: "best_available", rules: [] },
}, "policy");
await send("memory.record", {
  project_id: project, task_id: "task-a", record_id: "decision-a",
  category: "decision", content: "Use bounded evidence for the Mac dashboard",
  source: "user_decision", source_ref: "ui-fixture",
  visibility: "project", recorded_at: 1,
}, "memory");
for (const [sequence, task, tool, phase] of [
  [1, "task-a", "Read", "reported_success"],
  [2, "task-b", "git", "reported_unknown"],
  [3, "task-a", "Read", "reported_failure"],
]) {
  await send("invocation.observe", {
    event_id: `event-${sequence}`, invocation_id: `call-${sequence}`,
    project_id: project, task_id: task, execution_id: `execution-${sequence}`,
    provider: "codex", native_call_id: `native-${sequence}`,
    tool_name: tool, phase, source: "transcript", occurred_at: sequence,
  }, `event-${sequence}`);
}

process.stdout.write(`SOCKET=${socket}\nPROJECT=${project}\n`);
await new Promise(() => {});
