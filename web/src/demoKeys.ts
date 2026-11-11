// DUI can't send keyboard events; a Lua script forwards keys as {type:'demo-key', key, ctrl, shift} messages.
const focusable = 'input:not([disabled]),textarea:not([disabled]),select:not([disabled]),button:not([disabled]),a[href],[tabindex]:not([tabindex="-1"]),[contenteditable="true"]';
export function installDemoKeys() {
  window.addEventListener('message', event => {
    let msg = event.data;
    if (typeof msg === 'string') { try { msg = JSON.parse(msg); } catch { return; } }
    if (!msg || msg.type !== 'demo-key' || typeof msg.key !== 'string') return;
    const key: string = msg.key;
    const el = document.activeElement as HTMLInputElement | HTMLTextAreaElement | null;
    if (!el) return;
    if (key === 'Tab') {
      const list = [...document.querySelectorAll<HTMLElement>(focusable)].filter(node => node.offsetParent);
      const next = list[(list.indexOf(el) + (msg.shift ? list.length - 1 : 1)) % list.length]; next?.focus(); return;
    }
    const isText = el.tagName === 'INPUT' || el.tagName === 'TEXTAREA';
    if (!isText && !el.isContentEditable) return;
    const caret = (pos: number) => { try { el.setSelectionRange(pos, pos); } catch { /* input type has no selection */ } };
    if (key.length === 1 && !msg.ctrl) document.execCommand('insertText', false, key);
    else if (key === 'Backspace') document.execCommand('delete');
    else if (key === 'Delete') document.execCommand('forwardDelete');
    else if (isText && key === 'ArrowLeft') caret(Math.max(0, (el.selectionStart ?? 0) - 1));
    else if (isText && key === 'ArrowRight') caret((el.selectionEnd ?? 0) + 1);
    else if (isText && key === 'Home') caret(0);
    else if (isText && key === 'End') caret(el.value.length);
    else if (key === 'Enter') {
      if (el.tagName === 'TEXTAREA') document.execCommand('insertText', false, '\n');
      else { el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })); el.closest('form')?.requestSubmit(); }
    }
  });
}
