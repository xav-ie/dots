// Stdio entrypoint for stape-io/google-tag-manager-mcp-server, which upstream
// only ships as a Cloudflare Worker. The worker's OAuth provider exists to
// authenticate *remote* users; running it ourselves we only need a GTM access
// token, so we mint one from our own refresh token and hand the tools the same
// `props` object they expect.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { OAuth2Client } from "google-auth-library";
import { tools } from "./tools";
import { removeMCPServerData } from "./tools/removeMCPServerData";

const env = (name: string): string => {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is not set`);
  }
  return value;
};

const main = async (): Promise<void> => {
  const oauth = new OAuth2Client(
    env("GTM_CLIENT_ID"),
    env("GTM_CLIENT_SECRET"),
  );
  oauth.setCredentials({ refresh_token: env("GTM_REFRESH_TOKEN") });

  // Tools read props.accessToken synchronously at call time, so keep it fresh
  // out of band. getAccessToken() serves the cached token until it is within
  // 5 min of expiry, so a 5 min tick never hands out an expired one.
  const props = { accessToken: "" } as never as { accessToken: string };
  const refresh = async (): Promise<void> => {
    props.accessToken = (await oauth.getAccessToken()).token ?? "";
  };
  await refresh();
  setInterval(() => void refresh(), 5 * 60 * 1000).unref();

  const server = new McpServer({
    name: "google-tag-manager-mcp-server",
    version: "3.0.6",
  });

  tools
    // Worker-only: revokes access via the hosted server's /remove endpoint.
    .filter((register) => register !== removeMCPServerData)
    .forEach((register) =>
      // @ts-ignore — upstream registers with the same cast
      register(server, { props, env: {} }),
    );

  await server.connect(new StdioServerTransport());
};

void main();
