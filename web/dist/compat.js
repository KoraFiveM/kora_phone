// Compatibility shim for custom apps built against another phone's JS API
// (lb-phone/sd-phone-style `fetchNui`/`onNuiEvent`, plain globals for
// `resourceName`/`appName`/`settings`). It is a thin layer over the kora phone
// protocol (v1, window.postMessage); new apps should use @kora/phone-sdk.
// Add one script tag to your app's own index.html, as early as possible:
//   <script src="https://cfx-nui-kora_phone/compat.js"></script>
// This only reproduces the DATA bridge -- it does not reimplement any other
// phone's UI component library (popups, pickers, maps, etc).
(function () {
  var params = new URLSearchParams(window.location.search);
  var resourceName = params.get('npResource') || '';
  var appName = params.get('npApp') || '';
  var parentOrigin = params.get('npParent') || '';
  var SETTINGS_EVENT = 'kora:settings';
  var listeners = {};
  var settingsListeners = [];
  var settings = {};
  var pending = {};
  var counter = 0;

  function send(type, payload, id) {
    if (!window.parent || window.parent === window || !parentOrigin) return;
    window.parent.postMessage({ kora: 'phone', v: 1, id: id, type: type, payload: payload }, parentOrigin);
  }

  function request(type, payload) {
    var id = 'compat-' + (++counter) + '-' + Math.random().toString(36).slice(2);
    return new Promise(function (resolve, reject) {
      pending[id] = { resolve: resolve, reject: reject };
      send(type, payload || {}, id);
    });
  }

  function emit(name, data) {
    (listeners[name] || []).slice().forEach(function (cb) { cb(data); });
  }

  window.addEventListener('message', function (event) {
    if (event.source !== window.parent || event.origin !== parentOrigin) return;
    var msg = event.data;
    if (!msg || msg.kora !== 'phone' || msg.v !== 1) return;
    if (msg.type === 'response' && pending[msg.id]) {
      var entry = pending[msg.id];
      delete pending[msg.id];
      if (msg.ok) entry.resolve(msg.payload);
      else entry.reject(new Error((msg.error && msg.error.message) || 'Request failed'));
    } else if (msg.type === 'event' && msg.payload && typeof msg.payload.name === 'string') {
      if (msg.payload.name === SETTINGS_EVENT) {
        settings = msg.payload.data || {};
        window.settings = settings;
        settingsListeners.forEach(function (cb) { cb(settings); });
      } else {
        emit(msg.payload.name, msg.payload.data);
      }
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

  // Protocol access for legacy apps that want more than fetchNui.
  window.koraPhone = { request: request };

  request('ready').catch(function () {});
})();
