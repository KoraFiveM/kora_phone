// src/protocol.ts
var PROTOCOL_NAME = "phone";
var PROTOCOL_VERSION = 1;
var DEFAULT_HOST_ORIGIN = "https://cfx-nui-kora_phone";
var DEFAULT_TIMEOUT_MS = 1e4;
var PUSH_TYPES = ["init", "theme", "event", "visibility"];
function isEnvelope(value) {
  if (typeof value !== "object" || value === null) return false;
  const v = value;
  return v.kora === PROTOCOL_NAME && v.v === PROTOCOL_VERSION && typeof v.type === "string";
}

// src/client.ts
var PhoneError = class extends Error {
  constructor(code, message) {
    super(message);
    this.name = "PhoneError";
    this.code = code;
  }
};
function defaultId() {
  return globalThis.crypto.randomUUID();
}
function applyTheme(win, theme, applied = /* @__PURE__ */ new Set()) {
  const style = win.document?.documentElement.style;
  if (!style) return;
  for (const [name, value] of Object.entries(theme.vars)) {
    if (typeof value !== "string") continue;
    style.setProperty(name.startsWith("--") ? name : `--${name}`, value);
    applied.add(name);
  }
  style.setProperty("color-scheme", theme.scheme);
}
function createPhoneClient(options = {}) {
  const win = options.window ?? globalThis.window;
  if (!win) throw new PhoneError("NO_WINDOW", "createPhoneClient requires a window");
  const hostOrigin = options.hostOrigin ?? DEFAULT_HOST_ORIGIN;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const nextId = options.idFactory ?? defaultId;
  const pending = /* @__PURE__ */ new Map();
  const eventSubs = /* @__PURE__ */ new Map();
  const themeSubs = /* @__PURE__ */ new Set();
  const visibilitySubs = /* @__PURE__ */ new Set();
  let init = null;
  let theme = null;
  let destroyed = false;
  let readyPromise = null;
  let resolveInit = null;
  const initPromise = new Promise((resolve) => {
    resolveInit = resolve;
  });
  const handlePush = (type, payload) => {
    if (type === "init") {
      const p = payload;
      init = p;
      theme = p.theme;
      applyTheme(win, p.theme);
      resolveInit?.(p);
    } else if (type === "theme") {
      const p = payload;
      theme = p;
      applyTheme(win, p);
      themeSubs.forEach((cb) => cb(p));
    } else if (type === "event") {
      const p = payload;
      eventSubs.get(p.name)?.forEach((cb) => cb(p.data));
    } else if (type === "visibility") {
      const p = payload;
      visibilitySubs.forEach((cb) => cb(p.visible));
    }
  };
  const listener = (event) => {
    if (event.source !== win.parent) return;
    if (event.origin !== hostOrigin) return;
    const msg = event.data;
    if (!isEnvelope(msg)) return;
    const record = msg;
    if (msg.type === "response") {
      const id = record.id;
      if (typeof id !== "string") return;
      const entry = pending.get(id);
      if (!entry) return;
      pending.delete(id);
      clearTimeout(entry.timer);
      if (record.ok === true) {
        entry.resolve(record.payload);
      } else {
        const err = record.error;
        entry.reject(
          new PhoneError(
            typeof err?.code === "string" ? err.code : "REQUEST_FAILED",
            typeof err?.message === "string" ? err.message : "Request failed"
          )
        );
      }
      return;
    }
    if (PUSH_TYPES.includes(msg.type)) {
      handlePush(msg.type, record.payload);
    }
  };
  win.addEventListener("message", listener);
  function request(type, payload) {
    if (destroyed) return Promise.reject(new PhoneError("DESTROYED", "Phone client destroyed"));
    const id = nextId();
    const message = {
      kora: PROTOCOL_NAME,
      v: PROTOCOL_VERSION,
      id,
      type,
      ...payload === void 0 ? {} : { payload }
    };
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new PhoneError("TIMEOUT", `Request ${type} timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      pending.set(id, { resolve, reject, timer });
      win.parent.postMessage(message, hostOrigin);
    });
  }
  function subscribe(set, cb) {
    set.add(cb);
    return () => {
      set.delete(cb);
    };
  }
  return {
    ready() {
      if (!readyPromise) {
        readyPromise = request("ready", void 0).then(() => initPromise);
        readyPromise.catch(() => {
          readyPromise = null;
        });
      }
      return readyPromise;
    },
    get theme() {
      return theme;
    },
    get init() {
      return init;
    },
    async callback(name, payload) {
      return await request("callback", { name, payload });
    },
    async open(app, target) {
      await request("open", target === void 0 ? { app } : { app, target });
    },
    async system(action, payload) {
      return await request("system", { ...payload ?? {}, action });
    },
    async call(number) {
      await request("call", { number });
    },
    async refresh() {
      await request("refresh", {});
    },
    async client(name, payload) {
      return await request("client", { name, payload });
    },
    async notify(title, body) {
      await request("notify", { title, body });
    },
    storage: {
      async get(key) {
        const value = await request("storage.get", { key });
        return value ?? null;
      },
      async list(prefix) {
        return await request("storage.list", prefix === void 0 ? {} : { prefix }) ?? {};
      },
      async set(key, value) {
        await request("storage.set", { key, value });
      },
      async remove(key) {
        await request("storage.remove", { key });
      }
    },
    contacts: {
      async list() {
        return await request("contacts.list", void 0) ?? [];
      },
      async save(contact) {
        return await request("contacts.save", contact);
      }
    },
    on(name, cb) {
      let set = eventSubs.get(name);
      if (!set) {
        set = /* @__PURE__ */ new Set();
        eventSubs.set(name, set);
      }
      return subscribe(set, cb);
    },
    onTheme: (cb) => subscribe(themeSubs, cb),
    onVisibility: (cb) => subscribe(visibilitySubs, cb),
    async close() {
      await request("close", void 0);
    },
    async setTitle(title) {
      await request("setTitle", { title });
    },
    async haptic() {
      await request("haptic", {});
    },
    async getContext() {
      const ctx = await request("getContext", void 0);
      init = ctx;
      return ctx;
    },
    destroy() {
      destroyed = true;
      win.removeEventListener("message", listener);
      for (const [id, entry] of pending) {
        clearTimeout(entry.timer);
        entry.reject(new PhoneError("DESTROYED", "Phone client destroyed"));
        pending.delete(id);
      }
    }
  };
}
export {
  DEFAULT_HOST_ORIGIN,
  DEFAULT_TIMEOUT_MS,
  PROTOCOL_NAME,
  PROTOCOL_VERSION,
  PUSH_TYPES,
  PhoneError,
  applyTheme,
  createPhoneClient,
  isEnvelope
};
