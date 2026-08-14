#!/usr/bin/env node

import { spawn } from "node:child_process";
import { copyFile, mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const managedConfigPath = join(scriptDirectory, "config.managed.toml");
const userHome = process.env.HOME;
const codexHome = process.env.CODEX_HOME ?? (userHome ? join(userHome, ".codex") : null);
const skipClaudeImport = process.argv.includes("--skip-claude-import");

class AppServerClient {
  constructor(home) {
    this.home = home;
    this.nextRequestId = 1;
    this.pendingRequests = new Map();
    this.notificationWaiters = [];
    this.stderr = "";
    this.closing = false;
  }

  async start() {
    this.process = spawn("codex", ["app-server", "--strict-config", "--stdio"], {
      env: { ...process.env, CODEX_HOME: this.home },
      stdio: ["pipe", "pipe", "pipe"],
    });

    this.process.stderr.setEncoding("utf8");
    this.process.stderr.on("data", (chunk) => {
      this.stderr += chunk;
    });

    this.process.once("error", (error) => {
      this.rejectPending(error);
    });

    this.exitPromise = new Promise((resolve) => {
      this.process.once("exit", (code, signal) => {
        const details = this.stderr.trim();
        if (!this.closing || code !== 0 || signal) {
          this.rejectPending(
            new Error(
              `Codex app-server exited unexpectedly (${signal ?? `status ${code}`})${
                details ? `:\n${details}` : ""
              }`,
            ),
          );
        }
        resolve();
      });
    });

    const lines = createInterface({ input: this.process.stdout });
    lines.on("line", (line) => this.handleMessage(line));

    await this.request("initialize", {
      clientInfo: { name: "dotfiles-sync", version: "1" },
      capabilities: { experimentalApi: true },
    });
    this.notify("initialized");
  }

  handleMessage(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return;
    }

    if (Object.hasOwn(message, "id")) {
      const pending = this.pendingRequests.get(message.id);
      if (!pending) return;
      this.pendingRequests.delete(message.id);
      if (message.error) {
        pending.reject(new Error(`${pending.method}: ${message.error.message}`));
      } else {
        pending.resolve(message.result);
      }
      return;
    }

    if (!message.method) return;
    for (const waiter of [...this.notificationWaiters]) {
      if (waiter.method === message.method && waiter.predicate(message.params)) {
        this.notificationWaiters.splice(this.notificationWaiters.indexOf(waiter), 1);
        clearTimeout(waiter.timeout);
        waiter.resolve(message.params);
      }
    }
  }

  request(method, params = {}) {
    const id = this.nextRequestId++;
    const response = new Promise((resolve, reject) => {
      this.pendingRequests.set(id, { method, resolve, reject });
    });
    this.process.stdin.write(`${JSON.stringify({ id, method, params })}\n`);
    return response;
  }

  notify(method, params) {
    const message = params === undefined ? { method } : { method, params };
    this.process.stdin.write(`${JSON.stringify(message)}\n`);
  }

  waitForNotification(method, predicate = () => true, timeoutMs = 60_000) {
    return new Promise((resolve, reject) => {
      const waiter = { method, predicate, resolve, reject };
      waiter.timeout = setTimeout(() => {
        this.notificationWaiters.splice(this.notificationWaiters.indexOf(waiter), 1);
        reject(new Error(`Timed out waiting for ${method}`));
      }, timeoutMs);
      this.notificationWaiters.push(waiter);
    });
  }

  rejectPending(error) {
    for (const pending of this.pendingRequests.values()) pending.reject(error);
    this.pendingRequests.clear();
    for (const waiter of this.notificationWaiters) {
      clearTimeout(waiter.timeout);
      waiter.reject(error);
    }
    this.notificationWaiters = [];
  }

  async close() {
    if (
      !this.process ||
      this.process.exitCode !== null ||
      this.process.signalCode !== null
    ) {
      return;
    }
    this.closing = true;
    this.process.stdin.end();
    await this.exitPromise;
  }
}

async function readManagedLayer() {
  const temporaryHome = await mkdtemp(join(tmpdir(), "codex-managed-config-"));
  try {
    await copyFile(managedConfigPath, join(temporaryHome, "config.toml"));
    const client = new AppServerClient(temporaryHome);
    await client.start();
    try {
      const response = await client.request("config/read", { includeLayers: true });
      const userLayer = response.layers?.find(
        (layer) => layer.name?.type === "user" && layer.name.profile == null,
      );
      if (!userLayer) throw new Error("Codex did not return the managed user config layer");

      for (const [key, value] of Object.entries(userLayer.config)) {
        if (value !== null && typeof value === "object" && !Array.isArray(value)) {
          throw new Error(
            `Managed config key ${key} is a table; keep config.managed.toml to documented root values`,
          );
        }
      }
      return userLayer.config;
    } finally {
      await client.close();
    }
  } finally {
    await rm(temporaryHome, { recursive: true, force: true });
  }
}

async function importClaudeConfig(client) {
  const detection = await client.request("externalAgentConfig/detect", {
    includeHome: true,
    cwds: [],
    maxSessions: 0,
  });
  const migrationItems = detection.items.filter((item) => item.itemType !== "SESSIONS");
  if (migrationItems.length === 0) {
    console.log("> No Claude Code configuration found to import");
    return;
  }

  // This app-server instance initiates only one import, so its next completion
  // notification belongs to this request even if it arrives before the response.
  const completed = client.waitForNotification("externalAgentConfig/import/completed");
  const response = await client.request("externalAgentConfig/import", {
    migrationItems,
    providerId: "dotfiles",
    source: "dotfiles",
  });
  const result = await completed;
  if (result.importId !== response.importId) {
    throw new Error("Received a completion notification for an unexpected Claude Code import");
  }
  const failures = result.itemTypeResults.flatMap((item) => item.failures);
  if (failures.length > 0) {
    throw new Error(
      `Claude Code import failed:\n${failures.map((failure) => `- ${failure.itemType}: ${failure.message}`).join("\n")}`,
    );
  }
  console.log(
    `> Imported ${migrationItems.length} Claude Code configuration categories (sessions excluded)`,
  );
}

async function main() {
  if (!codexHome) throw new Error("HOME or CODEX_HOME must be set");
  await mkdir(codexHome, { recursive: true });
  const managedConfig = await readManagedLayer();
  const client = new AppServerClient(codexHome);
  await client.start();
  let importError;
  try {
    if (!skipClaudeImport) {
      try {
        await importClaudeConfig(client);
      } catch (error) {
        importError = error;
      }
    }
    const edits = Object.entries(managedConfig).map(([keyPath, value]) => ({
      keyPath,
      value,
      mergeStrategy: "replace",
    }));
    await client.request("config/batchWrite", { edits, reloadUserConfig: false });
  } finally {
    await client.close();
  }

  const validator = new AppServerClient(codexHome);
  await validator.start();
  try {
    await validator.request("config/read", {});
  } finally {
    await validator.close();
  }
  console.log(
    `> Synced ${Object.keys(managedConfig).length} managed Codex settings to ${join(codexHome, "config.toml")}`,
  );
  if (importError) throw importError;
}

main().catch((error) => {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
});
