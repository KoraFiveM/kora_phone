import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const resourceRoot = dirname(fileURLToPath(import.meta.url));
const developmentBase = "/@qbtheme";
const productionBase = "https://cfx-nui-kora_theme";
const runtimeVersion = "5";
const contentTypes = {
  css: "text/css; charset=utf-8",
  js: "text/javascript; charset=utf-8",
  json: "application/json; charset=utf-8",
  txt: "text/plain; charset=utf-8",
  woff2: "font/woff2",
};

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
        // dev server shows the same palette as the resource. fonts/ holds the
        // catalog, fonts.css (imported by theme.css) and the woff2 files.
        const name = ["theme.css", "theme.js", "theme.json"].find((file) => url === `${developmentBase}/${file}`)
          ?? url?.match(/^\/@qbtheme\/(fonts\/(?:[a-z0-9-]+\/)?[a-z0-9-]+\.(?:css|json|woff2|txt))$/)?.[1];
        if (!name) return next();
        let body;
        try {
          body = await readFile(join(resourceRoot, name));
        } catch {
          return next();
        }
        response.statusCode = 200;
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("Content-Type", contentTypes[name.slice(name.lastIndexOf(".") + 1)]);
        response.end(body);
      });
    },
  };
}
