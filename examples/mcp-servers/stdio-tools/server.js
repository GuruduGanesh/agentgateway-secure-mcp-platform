import { createInterface } from "node:readline";

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
      properties: {
        tenant: { type: "string" },
        note: { type: "string" }
      },
      required: ["tenant", "note"]
    }
  }
];

function result(id, payload) {
  process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id, result: payload })}\n`);
}

function error(id, code, message) {
  process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } })}\n`);
}

async function handle(message) {
  const { id, method, params = {} } = JSON.parse(message);

  if (method === "initialize") {
    result(id, {
      protocolVersion: "2025-06-18",
      capabilities: { tools: {} },
      serverInfo: { name: "stdio-demo-tools", version: "0.1.0" }
    });
    return;
  }

  if (method === "tools/list") {
    result(id, { tools });
    return;
  }

  if (method === "tools/call") {
    const name = params.name;
    const args = params.arguments ?? {};
    if (name === "read_incidents") {
      result(id, {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              tenant: args.tenant,
              incidents: [
                { id: "INC-1001", severity: "sev2", service: "payments", status: "investigating" },
                { id: "INC-1002", severity: "sev3", service: "search", status: "monitoring" }
              ]
            })
          }
        ]
      });
      return;
    }
    if (name === "write_incident_note") {
      result(id, {
        content: [
          {
            type: "text",
            text: JSON.stringify({ tenant: args.tenant, accepted: true, note: args.note })
          }
        ]
      });
      return;
    }
    error(id, -32602, `Unknown tool: ${name}`);
    return;
  }

  error(id, -32601, `Unsupported method: ${method}`);
}

const rl = createInterface({ input: process.stdin });
rl.on("line", (line) => {
  handle(line).catch((err) => error(null, -32603, err.message));
});
