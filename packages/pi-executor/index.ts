import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

const EXECUTOR_URL = "https://executor.lalala.casa/mcp";

export default function (pi: ExtensionAPI) {
  let client: Client | null = null;

  const getClient = async (): Promise<Client> => {
    if (client) return client;

    client = new Client(
      { name: "pi-executor", version: "1.0.0" },
      { capabilities: {} },
    );

    const transport = new StreamableHTTPClientTransport(new URL(EXECUTOR_URL));
    await client.connect(transport);

    return client;
  };

  const resetClient = async () => {
    if (client) {
      try {
        await client.close();
      } catch {
        // ignore cleanup errors
      }
      client = null;
    }
  };

  // Register the execute tool
  pi.registerTool({
    name: "executor_execute",
    label: "Executor",
    description: [
      "Execute TypeScript in sandbox; call tools via discovery workflow.",
      "Workflow:",
      '1) const matches = await tools.discover({ query: "<intent>", limit: 12 });',
      "2) const details = await tools.describe.tool({ path, includeSchemas: true });",
      "3) Call selected tools.<path>(input).",
      "4) To connect a source, call tools.executor.sources.add(...) for MCP, OpenAPI, or GraphQL APIs.",
      "5) If execution pauses for interaction, resume it with the returned resumePayload.",
      "Do not use fetch; use tools.* only.",
      "IMPORTANT: Only return values from function calls are visible. console.log() output is NOT available.",
    ].join("\n"),
    promptSnippet:
      "Execute TypeScript in executor sandbox with tool discovery (tools.discover → tools.describe.tool → tools.<path>)",
    promptGuidelines: [
      "Use executor_execute for running TypeScript code that calls external tools/APIs via the executor sandbox.",
      "The executor only returns data from function calls — console.log() and other console output does NOT work.",
      "Follow the discover → describe → call workflow to find and use available tools.",
      "If an execution pauses for interaction, use executor_resume with the returned resumePayload.",
    ],
    parameters: Type.Object({
      code: Type.String({
        description: "TypeScript code to execute in the sandbox",
      }),
    }),
    async execute(_toolCallId, params, signal) {
      try {
        const c = await getClient();
        const result = await c.callTool(
          { name: "execute", arguments: { code: params.code } },
          undefined,
          { signal: signal ?? undefined },
        );

        const text = (result.content as Array<{ type: string; text?: string }>)
          .filter((c) => c.type === "text" && c.text)
          .map((c) => c.text!)
          .join("\n");

        return {
          content: [
            { type: "text", text: text || "Execution completed (no output)" },
          ],
          details: {
            structuredContent: result.structuredContent ?? null,
            isError: result.isError ?? false,
          },
        };
      } catch (err) {
        throw new Error(
          `Executor MCP error: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    },
  });

  // Register the resume tool
  pi.registerTool({
    name: "executor_resume",
    label: "Executor Resume",
    description: [
      "Resume a paused executor execution using the resumePayload returned by executor_execute.",
      "Never call this without getting approval from the user first unless they explicitly state otherwise.",
    ].join("\n"),
    promptSnippet: "Resume a paused executor execution",
    parameters: Type.Object({
      resumePayload: Type.Object({
        executionId: Type.String({
          description: "Execution ID from a paused execution",
        }),
      }),
      response: Type.Optional(
        Type.Object({
          action: Type.Union([
            Type.Literal("accept"),
            Type.Literal("decline"),
            Type.Literal("cancel"),
          ]),
          content: Type.Optional(Type.Record(Type.String(), Type.Unknown())),
        }),
      ),
    }),
    async execute(_toolCallId, params, signal) {
      try {
        const c = await getClient();
        const result = await c.callTool(
          { name: "resume", arguments: params as Record<string, unknown> },
          undefined,
          { signal: signal ?? undefined },
        );

        const text = (result.content as Array<{ type: string; text?: string }>)
          .filter((c) => c.type === "text" && c.text)
          .map((c) => c.text!)
          .join("\n");

        return {
          content: [
            { type: "text", text: text || "Resume completed (no output)" },
          ],
          details: {
            structuredContent: result.structuredContent ?? null,
            isError: result.isError ?? false,
          },
        };
      } catch (err) {
        throw new Error(
          `Executor MCP resume error: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    },
  });

  // Cleanup on shutdown
  pi.on("session_shutdown", async () => {
    await resetClient();
  });

  // Reconnect on new sessions
  pi.on("session_start", async () => {
    await resetClient();
  });
}
