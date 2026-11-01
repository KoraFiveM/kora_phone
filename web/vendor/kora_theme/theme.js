(() => {
  "use strict";

  // theme.json is the only source of colours; nothing is embedded here. Read it
  // next to this script (so Vite dev serves its own copy) and default to the
  // kora_theme NUI origin.
  const providerUrl = (() => {
    try {
      const src = document.currentScript && document.currentScript.src;
      if (src && /\/theme\.js(\?|$)/.test(src)) return new URL("theme.json", src).href;
    } catch (_) { /* fall through to the NUI origin */ }
    return "https://cfx-nui-kora_theme/theme.json";
  })();
  const tokenName = /^[a-z][a-z0-9-]{0,63}$/;
  const hex = /^#[0-9a-f]{6}$/i;
  const retryDelay = 250;
  const retryCount = 40;
  const roles = ["background", "surface", "surfacePopover", "surfaceRaised", "surfaceHover", "foreground", "mutedForeground", "border", "borderStrong", "control", "controlHover", "primary", "success", "warning", "danger", "info", "armour"];
  let configured = {};
  let overrides = null;

  const number = (value) => Number.isInteger(value) ? String(value) : String(Math.round(value * 10) / 10);
  const colour = (value) => typeof value === "string" && hex.test(value) ? value.toUpperCase() : undefined;

  function hsl(hexValue, alpha, lightnessOffset = 0) {
    const red = parseInt(hexValue.slice(1, 3), 16) / 255;
    const green = parseInt(hexValue.slice(3, 5), 16) / 255;
    const blue = parseInt(hexValue.slice(5, 7), 16) / 255;
    const max = Math.max(red, green, blue), min = Math.min(red, green, blue), delta = max - min;
    let hue = 0, saturation = 0, lightness = (max + min) / 2;
    if (delta) {
      saturation = lightness > 0.5 ? delta / (2 - max - min) : delta / (max + min);
      if (max === red) hue = (green - blue) / delta + (green < blue ? 6 : 0);
      else if (max === green) hue = (blue - red) / delta + 2;
      else hue = (red - green) / delta + 4;
      hue /= 6;
    }
    lightness = Math.max(0, Math.min(100, lightness * 100 + lightnessOffset));
    const value = `${number(hue * 360)} ${number(saturation * 100)}% ${number(lightness)}%`;
    return alpha == null ? value : `${value} / ${number(alpha)}`;
  }

  const linear = (value) => value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  // Fixed dark text grey (16/255) used for primary-foreground contrast.
  const darkLuminance = linear(16 / 255);

  function luminance(hexValue) {
    const channel = (offset) => linear(parseInt(hexValue.slice(offset, offset + 2), 16) / 255);
    return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
  }

  function contrast(hexValue) {
    if (!hexValue) return undefined;
    const value = luminance(hexValue);
    return 1.05 / (value + 0.05) >= (value + 0.05) / (darkLuminance + 0.05) ? "0 0% 100%" : "0 0% 6.3%";
  }

  function tokensFrom(colours) {
    const c = {};
    for (const role of roles) c[role] = colour(colours[role]);
    // A role missing from theme.json leaves its tokens unset rather than
    // substituting a second copy of the palette.
    const token = (role, alpha, offset) => c[role] ? hsl(c[role], alpha, offset) : undefined;
    return {
      background: token("background"), foreground: token("foreground"), card: token("surface"), "card-foreground": token("foreground"), popover: token("surfacePopover"), "popover-foreground": token("foreground"), secondary: token("surfaceRaised"), "secondary-foreground": token("foreground"), muted: token("surfaceRaised"), "muted-foreground": token("mutedForeground"), accent: token("surfaceHover"), "accent-foreground": token("foreground"), border: token("border"), "border-strong": token("borderStrong"), input: token("control"), "control-border": token("control"), "control-border-hover": token("controlHover"), "surface-raised": token("surfaceRaised"), "surface-hover": token("surfaceHover"), hud: token("surface", 0.72), "modal-overlay": token("background", 0.68),
      primary: token("primary"), ring: token("primary"), "focus-ring": token("primary", 0.55), selection: token("primary", 0.35), "brand-hover": token("primary", null, -5.1), "brand-pressed": token("primary", null, -10.6), "brand-soft": token("primary", 0.14), "brand-border": token("primary", 0.45), "primary-foreground": contrast(c.primary),
      success: token("success"), "success-soft": token("success", 0.14), "success-border": token("success", 0.45), "success-foreground": contrast(c.success), warning: token("warning"), "warning-soft": token("warning", 0.14), "warning-border": token("warning", 0.45), "warning-foreground": contrast(c.warning), destructive: token("danger"), danger: token("danger"), "destructive-soft": token("danger", 0.14), "destructive-border": token("danger", 0.45), "destructive-foreground": contrast(c.danger), info: token("info"), "info-soft": token("info", 0.14), "info-border": token("info", 0.45), "info-foreground": contrast(c.info), armour: token("armour"), surface: token("surface", 0.97), "surface-panel": token("surfaceRaised", 0.98), "secondary-text": token("info"),
    };
  }

  function applyTokens(tokens) {
    if (!tokens || typeof tokens !== "object" || Array.isArray(tokens)) return;
    const root = document.documentElement.style;
    for (const [key, value] of Object.entries(tokens)) {
      if (tokenName.test(key) && typeof value === "string" && value.length <= 160) root.setProperty(`--${key}`, value);
    }
  }

  function applyConfigured() {
    const colours = { ...configured };
    if (typeof overrides === "string" && hex.test(overrides)) colours.primary = overrides;
    else if (overrides && typeof overrides === "object" && !Array.isArray(overrides)) {
      for (const role of roles) if (hex.test(overrides[role] || "")) colours[role] = overrides[role];
    }
    applyTokens(tokensFrom(colours));
  }

  async function loadPlayerTheme() {
    if (typeof GetParentResourceName !== "function") return;
    try {
      const response = await fetch(`https://${GetParentResourceName()}/qbtheme:ready`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: "{}",
      });
      const payload = response.ok && await response.json();
      if (payload && Object.prototype.hasOwnProperty.call(payload, "overrides")) {
        overrides = payload.overrides || null;
        applyConfigured();
      }
    } catch (_) {
      // Loading screens and other bridge-free pages only use the server theme.
    }
  }

  async function loadTheme(remaining = retryCount) {
    try {
      const response = await fetch(providerUrl);
      const payload = response.ok && await response.json();
      if (!payload || !payload.colors || typeof payload.colors !== "object") throw new Error("invalid theme.json");
      configured = payload.colors;
      applyConfigured();
      return true;
    } catch (error) {
      if (remaining > 0) window.setTimeout(() => void loadTheme(remaining - 1), retryDelay);
      else console.error("[qbtheme] could not load theme.json", error);
      return false;
    }
  }

  window.addEventListener("message", (event) => {
    if (event.origin !== "nui://game") return;
    if (event.data?.action === "qbtheme:override") {
      overrides = event.data.data || null;
      applyConfigured();
    } else if (event.data?.action === "qbtheme:refresh") {
      void loadTheme();
    }
  });

  window.QBTheme = Object.freeze({ applyTokens, refresh: () => loadTheme() });
  void loadTheme().then(() => loadPlayerTheme());
})();
