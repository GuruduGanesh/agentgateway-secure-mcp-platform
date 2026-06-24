import http from "node:http";

const port = Number(process.env.HTTP_TOOLS_PORT ?? 7001);

const tools = [
  {
    name: "read_service_health",
    description: "Read synthetic service health for a tenant.",
    inputSchema: {
      type: "object",
      properties: { tenant: { type: "string" } },
      required: ["tenant"]
    }
  },
  {
    name: "write_restart_request",
    description: "Create a synthetic restart request for an operator.",
    inputSchema: {
      type: "object",
      properties: {
        tenant: { type: "string" },
        service: { type: "string" }
      },
      required: ["tenant", "service"]
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
          serverInfo: { name: "http-demo-tools", version: "0.1.0" }
        }
      });
      return;
    }
    if (method === "tools/list") {
      send(res, 200, { jsonrpc: "2.0", id, result: { tools } });
      return;
    }
    if (method === "tools/call" && params.name === "read_service_health") {
      send(res, 200, {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify({ tenant: params.arguments?.tenant, service: "payments", status: "healthy" }) }]
        }
      });
      return;
    }
    if (method === "tools/call" && params.name === "write_restart_request") {
      send(res, 200, {
        jsonrpc: "2.0",
        id,
        result: {
          content: [{ type: "text", text: JSON.stringify({ tenant: params.arguments?.tenant, service: params.arguments?.service, requested: true }) }]
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
  console.log(`HTTP MCP demo server listening on http://localhost:${port}/mcp`);
});
