// HTTP (streamable-HTTP-style) MCP server for the "sqlite" incident tools.
//
// Why HTTP and not stdio: the official agentgateway container image is distroless
// (no node/shell), so a stdio target (`cmd: node ...`) cannot be spawned inside
// the gateway. Serving over HTTP lets the gateway federate this as an `mcp:` target.
// A pure-stdio variant remains in ../stdio-tools for local/standalone use.
import http from "node:http";

const port = Number(process.env.SQLITE_TOOLS_PORT ?? 7003);

const tools = [
  {
    name: "read_incidents",
    description: "Read demo incident rows for the caller tenant.",
    inputSchema: {
      type: "object",
      properties: { tenant: { type: "string" } },
      required: ["tenant"]
    }
  },
  {
    name: "write_incident_note",
    description: "Append a demo operator note for the caller tenant.",
    inputSchema: {
      type: "object",
      properties: { tenant: { type: "string" }, note: { type: "string" } },
      required: ["tenant", "note"]
    }
  }
];

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
}

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/healthz") {
    send(res, 200, { ok: true });
    return;
  }

  if (req.method === "POST" && (req.url === "/mcp" || req.url === "/mcp/")) {
    const rpc = await readBody(req);
    const { id, method, params = {} } = rpc;

    // JSON-RPC notifications have no id and must not get a response body.
    if (id === undefined || id === null) {
      res.writeHead(202).end();
      return;
    }

    if (method === "initialize") {
      send(res, 200, {
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: "2025-06-18",
          capabilities: { tools: {} },
          serverInfo: { name: "sqlite-demo-tools", version: "0.1.0" }
        }
      });
      return;
    }
    if (method === "tools/list") {
      send(res, 200, { jsonrpc: "2.0", id, result: { tools } });
      return;
    }
    if (method === "tools/call" && params.name === "read_incidents") {
      send(res, 200, {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify({
            tenant: params.arguments?.tenant,
            incidents: [
              { id: "INC-1001", severity: "sev2", service: "payments", status: "investigating" },
              { id: "INC-1002", severity: "sev3", service: "search", status: "monitoring" }
            ]
          }) }]
        }
      });
      return;
    }
    if (method === "tools/call" && params.name === "write_incident_note") {
      send(res, 200, {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify({
            tenant: params.arguments?.tenant,
            accepted: true,
            note: params.arguments?.note
          }) }]
        }
      });
      return;
    }
    send(res, 200, { jsonrpc: "2.0", id, error: { code: -32601, message: "Unsupported method/tool" } });
    return;
  }

  send(res, 404, { error: "not_found" });
});

server.listen(port, () => {
  console.log(`SQLite MCP demo server listening on http://localhost:${port}/mcp`);
});
