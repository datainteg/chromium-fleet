// Persistent refresh-token session store.
// Backed by a JSON file so sessions survive API restarts.
const fs = require("node:fs/promises");
const path = require("node:path");

let _sessionsFile = null;
let _sessions = new Map();
let _saveTimer = null;
let _dirty = false;

function _scheduleSave() {
  _dirty = true;
  if (_saveTimer) return;
  _saveTimer = setTimeout(async () => {
    _saveTimer = null;
    if (!_dirty || !_sessionsFile) return;
    _dirty = false;
    try {
      await fs.mkdir(path.dirname(_sessionsFile), { recursive: true });
      await fs.writeFile(_sessionsFile, JSON.stringify([..._sessions.entries()]), "utf8");
    } catch {
      // non-fatal — in-memory store still works
    }
  }, 2_000);
}

async function initSessions(sessionsFile) {
  _sessionsFile = sessionsFile || null;
  if (!_sessionsFile) return;
  try {
    const raw = await fs.readFile(_sessionsFile, "utf8");
    const entries = JSON.parse(raw);
    if (Array.isArray(entries)) {
      _sessions = new Map(entries);
    }
  } catch {
    _sessions = new Map();
  }
}

function getSessions() { return _sessions; }
function getSession(tokenId) { return _sessions.get(tokenId); }
function setSession(tokenId, session) { _sessions.set(tokenId, session); _scheduleSave(); }
function deleteSession(tokenId) { _sessions.delete(tokenId); _scheduleSave(); }

module.exports = { initSessions, getSessions, getSession, setSession, deleteSession };
