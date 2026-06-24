import http from "node:http";

const port = Number(process.env.OPENAPI_APP_PORT ?? 7002);

const openapi = `openapi: 3.0.3
info:
  title: Tenant Operations Demo API
  version: 0.1.0
servers:
  - url: /
paths:
  /tickets:
    get:
      operationId: readTickets
      parameters:
        - in: query
          name: tenant
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Demo tickets
    post:
      operationId: writeTicket
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [tenant, message]
              properties:
                tenant:
                  type: string
                message:
                  type: string
      responses:
        '200':
          description: Created ticket
`;

function send(res, status, body, type = "application/json") {
  res.writeHead(status, { "content-type": type });
  res.end(type === "application/json" ? JSON.stringify(body) : body);
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host}`);

  if (req.method === "GET" && url.pathname === "/healthz") {
    send(res, 200, { ok: true });
    return;
  }

  if (req.method === "GET" && url.pathname === "/openapi.yaml") {
    send(res, 200, openapi, "text/yaml");
    return;
  }

  if (req.method === "GET" && url.pathname === "/tickets") {
    const tenant = url.searchParams.get("tenant");
    send(res, 200, {
      tenant,
      tickets: [
        { id: "TCK-101", summary: "Rotate demo virtual key", status: "open" },
        { id: "TCK-102", summary: "Review MCP write tool policy", status: "in_review" }
      ]
    });
    return;
  }

  if (req.method === "POST" && url.pathname === "/tickets") {
    const body = await readBody(req);
    send(res, 200, { id: "TCK-999", tenant: body.tenant, message: body.message, created: true });
    return;
  }

  send(res, 404, { error: "not_found" });
});

server.listen(port, () => {
  console.log(`OpenAPI demo app listening on http://localhost:${port}`);
});
