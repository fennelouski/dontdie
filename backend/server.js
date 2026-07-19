'use strict';

const http = require('http');
const path = require('path');
const { Store } = require('./src/store');
const { createApp } = require('./src/app');

const PORT = Number(process.env.PORT) || 3000;
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');

const store = new Store(DATA_DIR);
const server = http.createServer(createApp(store));

server.listen(PORT, () => {
  console.log(`dontdie-backend listening on port ${PORT} (data: ${DATA_DIR})`);
});

function shutdown(signal) {
  console.log(`Received ${signal}, flushing data and shutting down...`);
  server.close(() => {
    store.flushSync();
    process.exit(0);
  });
  setTimeout(() => {
    store.flushSync();
    process.exit(0);
  }, 3000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
