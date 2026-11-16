// The client NUI bridge is split between client/nui.lua (local routes) and shared/routes.json (server routes).
// Contract tests that used to grep one big Lua table read this combined view instead: the Lua source plus the
// routes rendered in the old `['route'] = 'kora_phone:server:name'` shape and as RegisterNUICallback('route'.
const fs = require("node:fs");
const path = require("node:path");

const root = path.join(__dirname, "..", "..");
const routes = JSON.parse(fs.readFileSync(path.join(root, "shared/routes.json"), "utf8"));
const lua = fs.readFileSync(path.join(root, "client/nui.lua"), "utf8");

const rendered = routes
    .map((r) => `['${r.nui}'] = '${r.server}'\nRegisterNUICallback('${r.nui}'`)
    .join("\n");

const local = [...lua.matchAll(/(?:^|\s)(?:route|KoraPhone\.RegisterNui)\('([^']+)'/g)]
    .map((m) => `RegisterNUICallback('${m[1]}'`)
    .join("\n");

module.exports = { routes, lua, source: `${lua}\n${rendered}\n${local}\n` };
