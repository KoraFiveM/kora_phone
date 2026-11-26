// lb-phone UI compatibility layer. The phone injects this into an lb-phone custom app's page BEFORE the app's own
// scripts run (web/src/sdk/lbdoc.ts), so the globals lb-phone apps expect exist without the app changing a line:
//
//   resourceName, appName, appIdentifier, settings, fetchNui, onNuiEvent, onSettingsChange, formatPhoneNumber,
//   setApp, createCall and `components` (setPopUp, setContextMenu, setContactSelector, setGallery, setColorPicker,
//   setEmojiPickerVisible, setFullscreenImage, setHomeIndicatorVisible, ...).
//
// Dialogs are drawn with the Kora UI kit, so they follow kora_theme. Pieces that need another phone's backend
// (GameMap, createGameRender, GIF picker, uploadMedia, saveToGallery, AirShare component) reject with a clear error.
(function () {
  var cfg = window.__koraLb || {};
  var host = cfg.hostOrigin || location.origin;
  var settings = {};
  var settingsListeners = [];
  var eventListeners = {};
  var pending = {};
  var counter = 0;

  function post(type, payload, id) {
    if (!window.parent || window.parent === window) return;
    window.parent.postMessage({ kora: 'phone', v: 1, id: id, type: type, payload: payload }, host);
  }

  function request(type, payload) {
    var id = 'lb-' + (++counter) + '-' + Math.random().toString(36).slice(2);
    return new Promise(function (resolve, reject) {
      pending[id] = { resolve: resolve, reject: reject };
      post(type, payload || {}, id);
    });
  }

  function lb(action, args) { return request('lb', Object.assign({ action: action }, args || {})); }

  function applyTheme(theme) {
    if (!theme) return;
    var root = document.documentElement;
    Object.keys(theme.vars || {}).forEach(function (name) { root.style.setProperty(name, theme.vars[name]); });
    // lb-phone apps style themselves from data-theme, "dark" or "light".
    root.setAttribute('data-theme', theme.scheme === 'light' ? 'light' : 'dark');
  }

  function emit(name, data) {
    (eventListeners[name] || []).slice().forEach(function (callback) { callback(data); });
  }

  window.addEventListener('message', function (event) {
    if (event.source !== window.parent || event.origin !== host) return;
    var msg = event.data;
    if (!msg || msg.kora !== 'phone' || msg.v !== 1) return;
    if (msg.type === 'response' && pending[msg.id]) {
      var entry = pending[msg.id];
      delete pending[msg.id];
      if (msg.ok) entry.resolve(msg.payload);
      else entry.reject(new Error((msg.error && msg.error.message) || 'Request failed'));
    } else if (msg.type === 'init' || msg.type === 'theme') {
      applyTheme(msg.payload && msg.payload.theme ? msg.payload.theme : msg.payload);
    } else if (msg.type === 'event' && msg.payload && typeof msg.payload.name === 'string') {
      var name = msg.payload.name;
      if (name === 'kora:settings') {
        settings = msg.payload.data || {};
        window.settings = settings;
        settingsListeners.forEach(function (callback) { callback(settings); });
      } else if (name === 'kora:raw') {
        // SendCustomAppMessage payload as lb-phone delivers it: a plain `message` event on the window.
        window.dispatchEvent(new MessageEvent('message', { data: msg.payload.data }));
      } else {
        emit(name, msg.payload.data);
      }
    }
  });

  // The UI kit is only loaded when a dialog is first needed.
  var kitPromise;
  function kit() {
    if (!kitPromise) {
      ['kora-tokens.css', 'kora-components.css'].forEach(function (file) {
        var link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = host + '/sdk/runtime/' + file;
        document.head.appendChild(link);
      });
      kitPromise = import(host + '/sdk/runtime/kit.js');
    }
    return kitPromise;
  }

  function unsupported(name) {
    return function () {
      return Promise.reject(new Error(name + ' is not available in kora_phone'));
    };
  }

  var noop = function () {};
  var components = {
    setPopUp: function (options) { kit().then(function (k) { return k.popup(options || {}); }); },
    setContextMenu: function (options) { kit().then(function (k) { return k.contextMenu(options || {}); }); },
    setColorPicker: function (options) {
      options = options || {};
      kit().then(function (k) { return k.colorPicker(); }).then(function (color) {
        if (color && options.onSelect) options.onSelect(color);
        if (options.onClose) options.onClose(color);
      });
    },
    setContactSelector: function (options) {
      options = options || {};
      Promise.all([kit(), lb('contacts')]).then(function (parts) {
        var items = (parts[1] || []).map(function (contact) {
          var name = ((contact.firstname || '') + ' ' + (contact.lastname || '')).trim();
          return { title: name || contact.number, detail: contact.number, contact: contact };
        });
        return parts[0].pick({ title: 'Choose a contact', items: items, empty: 'No contacts yet' });
      }).then(function (chosen) { if (chosen && options.onSelect) options.onSelect(chosen.contact); });
    },
    setGallery: function (options) {
      options = options || {};
      Promise.all([kit(), lb('gallery')]).then(function (parts) {
        var items = (parts[1] || []).filter(function (photo) {
          return photo.isVideo ? options.includeVideos !== false : options.includeImages !== false;
        }).map(function (photo, index) { return { title: 'Photo ' + (index + 1), detail: photo.isVideo ? 'Video' : '', photo: photo }; });
        return parts[0].pick({ title: 'Choose from gallery', items: items, empty: 'Your gallery is empty' });
      }).then(function (chosen) {
        if (!chosen || !options.onSelect) return;
        options.onSelect(options.multiSelect ? [chosen.photo] : chosen.photo);
      });
    },
    setEmojiPickerVisible: function (options) {
      if (!options) return;
      kit().then(function (k) { return k.emojiPicker(); }).then(function (chosen) {
        if (chosen && options.onSelect) options.onSelect(chosen);
      });
    },
    setFullscreenImage: function (src) { kit().then(function (k) { return k.fullscreenImage(src); }); },
    setHomeIndicatorVisible: noop,
    setShareComponent: unsupported('components.setShareComponent'),
    setGifPickerVisible: unsupported('components.setGifPickerVisible'),
    createGameRender: unsupported('components.createGameRender'),
    uploadMedia: unsupported('components.uploadMedia'),
    saveToGallery: unsupported('components.saveToGallery'),
    GameMap: function () { throw new Error('components.GameMap is not available in kora_phone'); },
  };

  window.resourceName = cfg.resource || '';
  window.appName = cfg.name || '';
  window.appIdentifier = cfg.app || '';
  window.settings = settings;
  window.components = components;

  window.fetchNui = function (event, data, scriptName) {
    return fetch('https://' + (scriptName || window.resourceName) + '/' + event, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).then(function (response) { return response.json(); });
  };

  window.onNuiEvent = function (event, callback) {
    (eventListeners[event] = eventListeners[event] || []).push(callback);
    return function () { eventListeners[event] = (eventListeners[event] || []).filter(function (item) { return item !== callback; }); };
  };
  window.useNuiEvent = window.onNuiEvent;

  window.onSettingsChange = function (callback) {
    settingsListeners.push(callback);
    return function () { settingsListeners = settingsListeners.filter(function (item) { return item !== callback; }); };
  };

  window.formatPhoneNumber = function (number) {
    var digits = String(number == null ? '' : number).replace(/\D/g, '');
    return digits.length > 3 ? digits.slice(0, 3) + '-' + digits.slice(3) : digits;
  };

  window.setApp = function (target) {
    var app = typeof target === 'string' ? target : target && target.name;
    return lb('openApp', { app: app, data: target && target.data });
  };

  window.createCall = function (options) {
    options = options || {};
    return lb('call', { number: options.number, company: options.company, videoCall: options.videoCall === true });
  };

  // Hand the phone the page's own state: ready, then theme and settings arrive as pushes.
  request('ready').catch(noop);
})();
