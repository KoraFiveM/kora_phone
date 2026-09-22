// Optional data-bridge shim for custom apps built against another phone's
// JS API (lb-phone/sd-phone-style `fetchNui`/`onNuiEvent`, plain globals for
// `resourceName`/`appName`/`settings`). Add one script tag to your app's own
// index.html, as early as possible:
//   <script src="https://cfx-nui-qbphone/compat.js"></script>
// This only reproduces the DATA bridge -- it does not reimplement any other
// phone's UI component library (popups, pickers, maps, etc).
(function () {
  var params = new URLSearchParams(window.location.search);
  var resourceName = params.get('npResource') || '';
  var appName = params.get('npApp') || '';
  var parentOrigin = params.get('npParent') || '*';
  var listeners = {};
  var settingsListeners = [];
  var settings = {};

  window.addEventListener('message', function (event) {
    var data = event.data;
    if (!data || data.app !== appName) return;
    if (data.npBridge === 'settings') {
      settings = data.settings || {};
      settingsListeners.forEach(function (cb) { cb(settings); });
    } else if (data.npBridge === 'message' && data.data && typeof data.data.action === 'string') {
      (listeners[data.data.action] || []).forEach(function (cb) { cb(data.data.data); });
    }
  });

  window.resourceName = resourceName;
  window.appName = appName;
  window.settings = settings;

  window.fetchNui = function (event, data, targetResource) {
    return fetch('https://' + (targetResource || resourceName) + '/' + event, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then(function (r) { return r.json(); });
  };

  window.onNuiEvent = function (event, callback) {
    (listeners[event] = listeners[event] || []).push(callback);
    return function () {
      listeners[event] = (listeners[event] || []).filter(function (cb) { return cb !== callback; });
    };
  };
  window.useNuiEvent = window.onNuiEvent;

  window.onSettingsChange = function (callback) {
    settingsListeners.push(callback);
    return function () { settingsListeners = settingsListeners.filter(function (cb) { return cb !== callback; }); };
  };

  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ npBridge: 'ready', app: appName }, parentOrigin);
  }
})();
