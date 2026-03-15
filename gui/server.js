const express = require("express");
const http = require("http");
const { WebSocketServer } = require("ws");
const path = require("path");
const url = require("url");
const { getStatus } = require("./status");
const runner = require("./runner");

const PORT = process.env.PORT || 3456;
const app = express();
const server = http.createServer(app);

app.use(express.static(path.join(__dirname, "public")));
app.use(express.json());

// --- REST API ---

app.get("/api/status", async (_req, res) => {
  try {
    const status = await getStatus();
    res.json(status);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post("/api/action/:name", (req, res) => {
  try {
    const session = runner.runAction(req.params.name, req.body.args || []);
    res.json({ id: session.id });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

app.post("/api/terminal", (req, res) => {
  try {
    const session = runner.runTerminal(req.body.mountDir || null);
    res.json({ id: session.id });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// --- WebSocket ---

const wss = new WebSocketServer({ server });

wss.on("connection", (ws, req) => {
  const parsed = url.parse(req.url, true);
  const sessionId = parsed.query.id;

  if (!sessionId) {
    ws.send(JSON.stringify({ type: "error", message: "Falta session ID" }));
    ws.close();
    return;
  }

  const session = runner.getSession(sessionId);
  if (!session) {
    ws.send(
      JSON.stringify({ type: "error", message: "Sesion no encontrada" })
    );
    ws.close();
    return;
  }

  // Enviar buffer acumulado
  if (session.buffer) {
    ws.send(session.buffer);
  }

  // Si ya termino, notificar
  if (session.status === "exited") {
    ws.send(JSON.stringify({ type: "exit", code: session.exitCode }));
  }

  // Listener para nueva salida
  const onData = (data) => {
    if (ws.readyState === ws.OPEN) ws.send(data);
  };
  session.listeners.add(onData);

  // Input del cliente
  ws.on("message", (msg) => {
    const str = msg.toString();
    try {
      const parsed = JSON.parse(str);
      if (parsed.type === "resize" && session.status === "running") {
        session.term.resize(
          Math.max(parsed.cols, 10),
          Math.max(parsed.rows, 2)
        );
        return;
      }
    } catch (_) {}

    // Input de texto al terminal
    if (session.status === "running") {
      session.term.write(str);
    }
  });

  ws.on("close", () => {
    session.listeners.delete(onData);
  });
});

// --- Cleanup ---

process.on("SIGINT", () => {
  runner.cleanup();
  process.exit(0);
});

process.on("SIGTERM", () => {
  runner.cleanup();
  process.exit(0);
});

// --- Start ---

server.listen(PORT, () => {
  console.log(`Claude Sandbox GUI: http://localhost:${PORT}`);
});
