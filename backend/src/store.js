'use strict';

const fs = require('fs');
const path = require('path');

// JSON-file-backed store with atomic writes. Deliberately dependency-free:
// swap `Store` for a real database adapter (Postgres, DynamoDB, ...) behind
// the same method surface when traffic outgrows a single node.
class Store {
  constructor(dataDir) {
    this.dataDir = dataDir;
    this.filePath = path.join(dataDir, 'db.json');
    this.data = {
      devices: {},        // deviceId -> device record
      tokenIndex: {},     // sha256(token) -> deviceId
      phoneIndex: {},     // E.164 phone number -> deviceId
      sessions: {},       // sessionId -> drive session
      missedCalls: [],    // chronological missed-call log
      messages: []        // chronological auto-reply/SMS log
    };
    this._writeTimer = null;
    this._load();
  }

  _load() {
    fs.mkdirSync(this.dataDir, { recursive: true });
    if (fs.existsSync(this.filePath)) {
      const raw = fs.readFileSync(this.filePath, 'utf8');
      if (raw.trim().length > 0) {
        this.data = { ...this.data, ...JSON.parse(raw) };
      }
    }
  }

  // Debounced atomic persistence: write to a temp file, then rename.
  save() {
    if (this._writeTimer) return;
    this._writeTimer = setTimeout(() => {
      this._writeTimer = null;
      this.flushSync();
    }, 50);
    this._writeTimer.unref?.();
  }

  flushSync() {
    if (this._writeTimer) {
      clearTimeout(this._writeTimer);
      this._writeTimer = null;
    }
    const tmpPath = this.filePath + '.tmp';
    fs.writeFileSync(tmpPath, JSON.stringify(this.data, null, 2));
    fs.renameSync(tmpPath, this.filePath);
  }
}

module.exports = { Store };
