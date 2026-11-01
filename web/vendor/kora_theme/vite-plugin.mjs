import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const resourceRoot = dirname(fileURLToPath(import.meta.url));
const developmentBase = "/@qbtheme";
const productionBase = "https://cfx-nui-kora_theme";
const runtimeVersion = "4";

export default function qbtheme() {
  let command = "build";
  return {
    name: "qbtheme",
    enforce: "pre",
    configResolved(config) { command = config.command; },
    transformIndexHtml: {
      order: "pre",
      handler(html) {
        const base = command === "serve" ? developmentBase : productionBase;
        return html
          .replaceAll("__QBTHEME_BASE__", base)
          // The shared runtime is externally linked, so it has no Vite content
          // hash. Version it explicitly to prevent CEF retaining an older
          // loader across reconnects.
          .replaceAll(`${base}/theme.js`, `${base}/theme.js?v=${runtimeVersion}`);
      },
    },
    configureServer(server) {
      server.middlewares.use(async (request, response, next) => {
        const url = request.url?.split("?", 1)[0];
        // theme.json is served too: theme.js reads the colours from it, so the
        // dev server shows the same palette as the resource.
        const name = ["theme.css", "theme.js", "theme.json"].find((file) => url === `${developmentBase}/${file}`);
        if (!name) return next();
        response.statusCode = 200;
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("Content-Type", name.endsWith(".css") ? "text/css; charset=utf-8" : name.endsWith(".json") ? "application/json; charset=utf-8" : "text/javascript; charset=utf-8");
        response.end(await readFile(join(resourceRoot, name)));
      });
    },
  };
}
