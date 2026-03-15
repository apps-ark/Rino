/* global Terminal, FitAddon */

(function () {
  "use strict";

  // --- State ---
  let actionSession = null;
  let terminalSession = null;
  let actionTerm = null;
  let mainTerm = null;
  let actionWs = null;
  let terminalWs = null;

  // --- DOM ---
  const $ = (s) => document.querySelector(s);
  const statusBadge = $("#status-badge");
  const stOs = $("#st-os");
  const stTool = $("#st-tool");
  const stBase = $("#st-base");
  const stAuth = $("#st-auth");
  const btnSetup = $("#btn-setup");
  const btnLogin = $("#btn-login");
  const btnStopAction = $("#btn-stop-action");
  const btnLaunch = $("#btn-launch");
  const btnStopTerminal = $("#btn-stop-terminal");
  const mountDir = $("#mount-dir");

  // --- Tabs ---
  document.querySelectorAll(".tab").forEach((tab) => {
    tab.addEventListener("click", () => {
      document.querySelectorAll(".tab").forEach((t) => t.classList.remove("active"));
      document.querySelectorAll(".tab-content").forEach((c) => c.classList.remove("active"));
      tab.classList.add("active");
      const target = tab.dataset.tab;
      $(`#tab-${target}`).classList.add("active");

      // Fit terminal on tab switch
      requestAnimationFrame(() => {
        if (target === "actions" && actionTerm) actionTerm.fit?.();
        if (target === "terminal" && mainTerm) mainTerm.fit?.();
      });
    });
  });

  // --- Terminal Factory ---
  function createTerminal(container) {
    const term = new Terminal({
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
    term.open(container);
    fitAddon.fit();

    term.fit = () => fitAddon.fit();

    return term;
  }

  // --- WebSocket ---
  function connectWs(sessionId, term, onExit) {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    const ws = new WebSocket(`${proto}//${location.host}/ws?id=${sessionId}`);

    ws.onmessage = (e) => {
      const data = e.data;
      // Check for JSON control messages
      if (data.startsWith("{")) {
        try {
          const msg = JSON.parse(data);
          if (msg.type === "exit") {
            term.writeln(`\r\n\x1b[90m--- Proceso terminado (codigo: ${msg.code}) ---\x1b[0m`);
            if (onExit) onExit(msg.code);
            return;
          }
          if (msg.type === "error") {
            term.writeln(`\r\n\x1b[31mError: ${msg.message}\x1b[0m`);
            return;
          }
        } catch (_) {
          // Not JSON, treat as terminal output
        }
      }
      term.write(data);
    };

    ws.onclose = () => {
      term.writeln("\r\n\x1b[90m--- Conexion cerrada ---\x1b[0m");
    };

    // Forward terminal input to WebSocket
    term.onData((data) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(data);
    });

    // Forward resize events
    term.onResize(({ cols, rows }) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "resize", cols, rows }));
      }
    });

    return ws;
  }

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
        ? `${dot("green")}Lista`
        : `${dot("gray")}Pendiente`;

      stAuth.innerHTML = s.setup.authReady
        ? `${dot("green")}Lista`
        : `${dot("gray")}Pendiente`;

      // Badge
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

      // Button states
      btnLogin.disabled = !s.setup.baseReady || !!actionSession;
      btnLaunch.disabled = !s.setup.baseReady;
    } catch (_) {
      statusBadge.className = "badge badge-error";
      statusBadge.textContent = "Error";
    }
  }

  function dot(color) {
    return `<span class="dot dot-${color}"></span>`;
  }

  // --- Actions ---
  async function runAction(name) {
    // Init terminal if needed
    if (!actionTerm) {
      actionTerm = createTerminal($("#action-terminal"));
    } else {
      actionTerm.clear();
    }

    btnSetup.disabled = true;
    btnLogin.disabled = true;
    btnStopAction.style.display = "";

    try {
      const res = await fetch(`/api/action/${name}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });
      const { id } = await res.json();
      actionSession = id;

      actionWs = connectWs(id, actionTerm, () => {
        actionSession = null;
        btnStopAction.style.display = "none";
        btnSetup.disabled = false;
        refreshStatus();
      });

      // Fit after connection
      requestAnimationFrame(() => actionTerm.fit());
    } catch (err) {
      actionTerm.writeln(`\x1b[31mError: ${err.message}\x1b[0m`);
      btnSetup.disabled = false;
      btnStopAction.style.display = "none";
    }
  }

  btnSetup.addEventListener("click", () => runAction("setup"));
  btnLogin.addEventListener("click", () => runAction("login"));

  btnStopAction.addEventListener("click", () => {
    if (actionWs) actionWs.close();
    actionSession = null;
    btnStopAction.style.display = "none";
    btnSetup.disabled = false;
    refreshStatus();
  });

  // --- Terminal ---
  btnLaunch.addEventListener("click", async () => {
    if (!mainTerm) {
      mainTerm = createTerminal($("#main-terminal"));
    } else {
      mainTerm.clear();
    }

    btnLaunch.disabled = true;
    btnStopTerminal.style.display = "";

    try {
      const res = await fetch("/api/terminal", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mountDir: mountDir.value || null }),
      });
      const { id } = await res.json();
      terminalSession = id;

      terminalWs = connectWs(id, mainTerm, () => {
        terminalSession = null;
        btnLaunch.disabled = false;
        btnStopTerminal.style.display = "none";
        refreshStatus();
      });

      requestAnimationFrame(() => mainTerm.fit());
      mainTerm.focus();
    } catch (err) {
      mainTerm.writeln(`\x1b[31mError: ${err.message}\x1b[0m`);
      btnLaunch.disabled = false;
      btnStopTerminal.style.display = "none";
    }
  });

  btnStopTerminal.addEventListener("click", () => {
    if (terminalWs) terminalWs.close();
    terminalSession = null;
    btnLaunch.disabled = false;
    btnStopTerminal.style.display = "none";
    refreshStatus();
  });

  // --- Resize handling ---
  window.addEventListener("resize", () => {
    if (actionTerm && $("#tab-actions").classList.contains("active")) {
      actionTerm.fit();
    }
    if (mainTerm && $("#tab-terminal").classList.contains("active")) {
      mainTerm.fit();
    }
  });

  // --- Init ---
  refreshStatus();
  setInterval(refreshStatus, 10000);
})();
