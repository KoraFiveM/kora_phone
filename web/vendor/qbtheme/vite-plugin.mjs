import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const resourceRoot = dirname(fileURLToPath(import.meta.url));
const developmentBase = "/@qbtheme";
const productionBase = "https://cfx-nui-qbtheme";
const runtimeVersion = "3";

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
        const name = url === `${developmentBase}/theme.css`
          ? "theme.css"
          : url === `${developmentBase}/theme.js` ? "theme.js"
          : url === `${developmentBase}/theme.json` ? "theme.json" : null;
        if (!name) return next();
        response.statusCode = 200;
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("Content-Type", name.endsWith(".css") ? "text/css; charset=utf-8" : name.endsWith('.json') ? 'application/json' : "text/javascript; charset=utf-8");
        const contents=await readFile(join(resourceRoot,name),'utf8');
        response.end(name==='theme.js' ? contents.replace(`${productionBase}/theme.json`,`${developmentBase}/theme.json`) : contents);
      });
    },
  };
}
