/** What the shim needs to know about the app it is injected into. */
export interface LbDocumentConfig {
    /** Resource that registered the app (where its NUI callbacks live). */
    resource: string;
    /** Path of the page inside the resource, for resolving the page's relative URLs. */
    ui: string;
    /** App identifier and display name, exposed as `appIdentifier` / `appName`. */
    app: string;
    name: string;
    /** Origin of the phone page the app talks to. */
    hostOrigin: string;
}

const escapeScript = (value: string): string => value.replace(/<\/(script)/gi, '<\\/$1').replace(/<!--/g, '<\\!--');

/** `https://cfx-nui-<resource>/<directory of ui>/`, the base every relative URL in the app resolves against. */
export function baseUrl(resource: string, ui: string): string {
    const directory = ui.replace(/^\/+/, '').split('/').slice(0, -1).join('/');
    return `https://cfx-nui-${resource}/${directory ? `${directory}/` : ''}`;
}

/**
 * Returns the app's own HTML with, ahead of everything else in <head>: a <base> (so its relative assets keep loading
 * from its resource), the config and the lb-phone shim. The shim therefore runs before any script the app ships.
 */
export function buildLbDocument(html: string, config: LbDocumentConfig, shim: string): string {
    const injected = `<base href="${baseUrl(config.resource, config.ui)}"><script>window.__koraLb=${escapeScript(JSON.stringify(config))};</script><script>${escapeScript(shim)}</script>`;
    const head = /<head(\s[^>]*)?>/i.exec(html);
    if (head) return html.slice(0, head.index + head[0].length) + injected + html.slice(head.index + head[0].length);
    const root = /<html(\s[^>]*)?>/i.exec(html);
    if (root) return html.slice(0, root.index + root[0].length) + `<head>${injected}</head>` + html.slice(root.index + root[0].length);
    return `<!doctype html><html><head>${injected}</head><body>${html}</body></html>`;
}
