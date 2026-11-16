// Lua route registration appears as `bind('name', ...)`, `KoraPhone.Routes.handle('name', ...)` or the
// deprecated `registerCallback('name', ...)` shim. This is the one pattern contract tests use for all three.
const bound = (name) => new RegExp(`(?:registerCallback|bind|Routes\\.handle)\\('${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}'`);
module.exports = { bound };
