/* global Terminal, FitAddon */

(function () {
  "use strict";

  // --- State ---
  let currentSession = null;
  let currentWs = null;
  let term = null;

  // --- DOM ---
  const $ = (s) => document.querySelector(s);
  const statusBadge = $("#status-badge");
  const stOs = $("#st-os");
  const stTool = $("#st-tool");
  const stBase = $("#st-base");
  const stAuth = $("#st-auth");
  const btnSetup = $("#btn-setup");
  const btnLogin = $("#btn-login");
  const btnLaunch = $("#btn-launch");
  const btnClaude = $("#btn-claude");
  const btnStop = $("#btn-stop");
  const mountDir = $("#mount-dir");

  // --- Terminal ---
  function ensureTerminal() {
    if (term) return term;
    term = new Terminal({
      theme: {
        background: "#000000",
        foreground: "#e6edf3",
        cursor: "#c084fc",
        cursorAccent: "#000000",
        selectionBackground: "#c084fc44",
        black: "#0d1117",
        red: "#f85149",
        green: "#3fb950",
        yellow: "#d29922",
        blue: "#58a6ff",
        magenta: "#c084fc",
        cyan: "#39d353",
        white: "#e6edf3",
        brightBlack: "#8b949e",
        brightRed: "#f85149",
        brightGreen: "#3fb950",
        brightYellow: "#d29922",
        brightBlue: "#58a6ff",
        brightMagenta: "#c084fc",
        brightCyan: "#39d353",
        brightWhite: "#ffffff",
      },
      fontFamily: '"SF Mono", "Fira Code", "Cascadia Code", "JetBrains Mono", monospace',
      fontSize: 14,
      lineHeight: 1.3,
      cursorBlink: true,
      cursorStyle: "bar",
      scrollback: 10000,
    });

    const fitAddon = new FitAddon.FitAddon();
    term.loadAddon(fitAddon);
    term.open($("#terminal"));
    fitAddon.fit();
    term.fit = () => fitAddon.fit();

    return term;
  }

  // --- Run action ---
  async function run(action, args) {
    // Stop any existing session
    stop();

    const t = ensureTerminal();
    t.clear();
    t.focus();

    setRunning(true);

    try {
      const res = await fetch(`/api/action/${action}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ args: args || [] }),
      });

      const data = await res.json();

      if (!res.ok || !data.id) {
        t.writeln(`\x1b[31mError: ${data.error || "No se pudo iniciar"}\x1b[0m`);
        setRunning(false);
        return;
      }

      currentSession = data.id;

      const proto = location.protocol === "https:" ? "wss:" : "ws:";
      currentWs = new WebSocket(`${proto}//${location.host}/ws?id=${data.id}`);

      currentWs.onopen = () => {
        currentWs.send(JSON.stringify({ type: "resize", cols: t.cols, rows: t.rows }));
      };

      currentWs.onmessage = (e) => {
        const d = e.data;
        if (d.startsWith("{")) {
          try {
            const msg = JSON.parse(d);
            if (msg.type === "exit") {
              t.writeln(`\r\n\x1b[90m--- Finalizado (codigo: ${msg.code}) ---\x1b[0m`);
              setRunning(false);
              refreshStatus();
              return;
            }
            if (msg.type === "error") {
              t.writeln(`\r\n\x1b[31m${msg.message}\x1b[0m`);
              setRunning(false);
              return;
            }
          } catch (_) {}
        }
        t.write(d);
      };

      currentWs.onerror = () => {
        t.writeln("\r\n\x1b[31mError de conexion\x1b[0m");
        setRunning(false);
      };

      currentWs.onclose = () => {};

      t.onData((d) => {
        if (currentWs && currentWs.readyState === WebSocket.OPEN) currentWs.send(d);
      });

      t.onResize(({ cols, rows }) => {
        if (currentWs && currentWs.readyState === WebSocket.OPEN) {
          currentWs.send(JSON.stringify({ type: "resize", cols, rows }));
        }
      });

      requestAnimationFrame(() => t.fit());
    } catch (err) {
      t.writeln(`\x1b[31mError: ${err.message}\x1b[0m`);
      setRunning(false);
    }
  }

  function stop() {
    if (currentWs) {
      currentWs.close();
      currentWs = null;
    }
    currentSession = null;
    setRunning(false);
  }

  function setRunning(running) {
    btnSetup.disabled = running;
    btnLogin.disabled = running;
    btnLaunch.disabled = running;
    btnClaude.disabled = running;
    btnStop.style.display = running ? "" : "none";
  }

  // --- Buttons ---
  btnSetup.addEventListener("click", () => run("setup"));
  btnLogin.addEventListener("click", () => run("login"));
  btnLaunch.addEventListener("click", () => {
    const args = mountDir.value ? [mountDir.value] : [];
    run("start", args);
  });
  btnClaude.addEventListener("click", () => {
    const args = mountDir.value ? [mountDir.value] : [];
    run("claude", args);
  });
  btnStop.addEventListener("click", () => {
    stop();
    refreshStatus();
  });

  // --- Status ---
  async function refreshStatus() {
    try {
      const res = await fetch("/api/status");
      const s = await res.json();

      stOs.innerHTML = `${s.os} (${s.arch})`;

      if (s.platform.installed) {
        stTool.innerHTML = `${dot("green")}${s.platform.tool} ${s.platform.version || ""}`;
      } else {
        stTool.innerHTML = `${dot("red")}${s.platform.tool} no instalado`;
      }

      stBase.innerHTML = s.setup.baseReady
        ? `${dot("green")}Listo`
        : `${dot("gray")}Pendiente`;

      stAuth.innerHTML = s.setup.authReady
        ? `${dot("green")}Activa`
        : `${dot("gray")}Pendiente`;

      if (!s.platform.installed) {
        statusBadge.className = "badge badge-error";
        statusBadge.textContent = "No configurado";
      } else if (s.setup.authReady) {
        statusBadge.className = "badge badge-ready";
        statusBadge.textContent = "Listo";
      } else if (s.setup.baseReady) {
        statusBadge.className = "badge badge-partial";
        statusBadge.textContent = "Falta login";
      } else {
        statusBadge.className = "badge badge-partial";
        statusBadge.textContent = "Falta setup";
      }
    } catch (_) {
      statusBadge.className = "badge badge-error";
      statusBadge.textContent = "Error";
    }
  }

  function dot(color) {
    return `<span class="dot dot-${color}"></span>`;
  }

  // --- Resize ---
  window.addEventListener("resize", () => {
    if (term) term.fit();
  });

  // --- Init ---
  refreshStatus();
  setInterval(refreshStatus, 10000);
})();
