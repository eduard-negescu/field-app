const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

// Drizzle's migration files.
config.resolver.sourceExts.push('sql');
// expo-sqlite on the web runs SQLite compiled to WebAssembly...
config.resolver.assetExts.push('wasm');
// ...which needs a cross-origin-isolated page (SharedArrayBuffer): two headers
// on every response of the development server. Set where Node writes every
// response's head, so they arrive whoever answers: since expo 58.0.19, the
// Expo CLI answers the page itself, before any Metro middleware runs.
const { ServerResponse } = require('node:http');
const writeHead = ServerResponse.prototype.writeHead;
ServerResponse.prototype.writeHead = function (...args) {
  this.setHeader('Cross-Origin-Embedder-Policy', 'credentialless');
  this.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  return writeHead.apply(this, args);
};

module.exports = config;
