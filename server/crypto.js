const crypto = require('node:crypto');
exports('randomHex', (bytes = 32) => crypto.randomBytes(Math.max(16, Math.min(64, bytes))).toString('hex'));
exports('pinHash', (pin) => {
  const salt = crypto.randomBytes(16).toString('hex');
  return `${salt}:${crypto.scryptSync(String(pin), salt + GetConvar('kora_phone_pin_pepper', ''), 32).toString('hex')}`;
});
exports('pinVerify', (pin, stored) => {
  try {
    const [salt, key] = String(stored).split(':');
    const expected = Buffer.from(key, 'hex');
    const actual = crypto.scryptSync(String(pin), salt + GetConvar('kora_phone_pin_pepper', ''), 32);
    return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
  } catch { return false; }
});
exports('turnCredentials', (subject) => {
  const secret = GetConvar('kora_phone_turn_secret', '');
  if (!secret) return null;
  const username = `${Math.floor(Date.now()/1000)+3600}:${String(subject)}`;
  return { username, credential: crypto.createHmac('sha1', secret).update(username).digest('base64') };
});
