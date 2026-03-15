const pty = require("node-pty");
const path = require("path");
const crypto = require("crypto");

const PROJECT_ROOT = path.resolve(__dirname, "..");
const sessions = new Map();

function createSession(command, args = []) {
  const id = crypto.randomUUID();
  const shell = process.env.SHELL || "/bin/bash";

  const term = pty.spawn(shell, ["-c", `${command} ${args.join(" ")}`], {
    name: "xterm-256color",
    cols: 120,
    rows: 30,
    cwd: PROJECT_ROOT,
    env: { ...process.env, FORCE_COLOR: "1" },
  });

  const session = {
    id,
    term,
    status: "running",
    exitCode: null,
    buffer: "",
    listeners: new Set(),
  };

  term.onData((data) => {
    // Mantener buffer circular de ~50KB
    session.buffer += data;
    if (session.buffer.length > 50000) {
      session.buffer = session.buffer.slice(-40000);
    }
    for (const fn of session.listeners) fn(data);
  });

  term.onExit(({ exitCode }) => {
    session.status = "exited";
    session.exitCode = exitCode;
    for (const fn of session.listeners) {
      fn(JSON.stringify({ type: "exit", code: exitCode }));
    }
  });

  sessions.set(id, session);
  return session;
}

function runAction(name, args = []) {
  const scripts = {
    setup: "./setup.sh",
    login: "./login.sh",
  };

  const script = scripts[name];
  if (!script) throw new Error(`Accion desconocida: ${name}`);
  return createSession(script, args);
}

function runTerminal(mountDir) {
  const args = mountDir ? [mountDir] : [];
  return createSession("./start.sh", args);
}

function getSession(id) {
  return sessions.get(id) || null;
}

function killSession(id) {
  const session = sessions.get(id);
  if (session && session.status === "running") {
    session.term.kill();
  }
  sessions.delete(id);
}

function cleanup() {
  for (const [id, session] of sessions) {
    if (session.status === "running") {
      try {
        session.term.kill();
      } catch (_) {}
    }
  }
  sessions.clear();
}

module.exports = { runAction, runTerminal, getSession, killSession, cleanup };
