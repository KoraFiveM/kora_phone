// Web screens move between folders as the UI is reorganised. Contract tests name a file by its old path
// (`web/src/Communication.tsx`); this resolves it to wherever the file lives now, by basename under web/src.
const fs = require("node:fs");
const path = require("node:path");

function find(dir, base) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.name === "node_modules") continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) { const hit = find(full, base); if (hit) return hit; }
        else if (entry.name === base) return full;
    }
    return undefined;
}

/** Absolute path for a `web/src/...` file, following it if it moved. Unknown files return the original path. */
function resolveWeb(root, rel) {
    const direct = path.join(root, rel);
    if (fs.existsSync(direct) || !rel.startsWith("web/src/")) return direct;
    return find(path.join(root, "web/src"), path.basename(rel)) || direct;
}

module.exports = { resolveWeb };
