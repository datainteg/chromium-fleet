const path = require("node:path");

function parseBoolean(value, fallback = false) {
  if (typeof value !== "string") {
    return fallback;
  }

  const normalized = value.trim().toLowerCase();
  if (["1", "true", "yes", "y", "on"].includes(normalized)) {
    return true;
  }
  if (["0", "false", "no", "n", "off"].includes(normalized)) {
    return false;
  }

  return fallback;
}

function parsePositiveInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  if (Number.isFinite(parsed) && parsed > 0) {
    return parsed;
  }
  return fallback;
}

function parseOrigins(value) {
  if (typeof value !== "string" || value.trim() === "") {
    return [];
  }
  return value
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
}

const config = {
  port: parsePositiveInt(process.env.PORT, 8787),
  host: process.env.HOST || "0.0.0.0",
  apiKey: process.env.API_KEY || "",
  disableAuth: parseBoolean(process.env.DISABLE_AUTH, false),
  allowInstall: parseBoolean(process.env.ALLOW_INSTALL, true),
  allowUninstall: parseBoolean(process.env.ALLOW_UNINSTALL, true),
  allowActions: parseBoolean(process.env.ALLOW_ACTIONS, true),
  commandTimeoutMs: parsePositiveInt(process.env.COMMAND_TIMEOUT_MS, 15 * 60 * 1000),
  sellerRoot: process.env.SELLER_ROOT || "/opt",
  fleetRoot: path.resolve(__dirname, "..", ".."),
  corsOrigins: parseOrigins(process.env.CORS_ORIGINS)
};

module.exports = { config };
