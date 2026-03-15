const { execFile } = require("child_process");
const os = require("os");

function run(cmd, args, timeout = 5000) {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout }, (err, stdout) => {
      if (err) return resolve({ ok: false, out: "" });
      resolve({ ok: true, out: stdout.trim() });
    });
  });
}

async function getStatus() {
  const platform = os.platform();
  const isMac = platform === "darwin";

  const status = {
    os: isMac ? "macOS" : "Linux",
    arch: os.arch(),
    platform: {
      tool: isMac ? "shuru" : "docker",
      installed: false,
      version: null,
      running: true,
    },
    setup: {
      baseReady: false,
      authReady: false,
    },
    sandbox: {
      running: false,
    },
  };

  if (isMac) {
    const ver = await run("shuru", ["--version"]);
    status.platform.installed = ver.ok;
    status.platform.version = ver.ok ? ver.out : null;

    if (ver.ok) {
      const list = await run("shuru", ["checkpoint", "list"]);
      if (list.ok) {
        status.setup.baseReady = list.out.includes("claude-ready");
        status.setup.authReady = list.out.includes("claude-authed");
      }
    }
  } else {
    const ver = await run("docker", ["--version"]);
    status.platform.installed = ver.ok;
    status.platform.version = ver.ok
      ? ver.out.match(/Docker version ([^,]+)/)?.[1] || ver.out
      : null;

    const info = await run("docker", ["info"]);
    status.platform.running = info.ok;

    if (info.ok) {
      const img = await run("docker", [
        "image",
        "inspect",
        "claude-sandbox",
      ]);
      status.setup.baseReady = img.ok;

      const vol = await run("docker", [
        "volume",
        "inspect",
        "claude-sandbox-auth",
      ]);
      status.setup.authReady = vol.ok;

      const ps = await run("docker", [
        "ps",
        "--filter",
        "name=claude-sandbox",
        "--format",
        "{{.ID}}",
      ]);
      status.sandbox.running = ps.ok && ps.out.length > 0;
    }
  }

  return status;
}

module.exports = { getStatus };
