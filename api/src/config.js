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

function clampPositiveInt(value, min, max, fallback) {
  const parsed = parsePositiveInt(value, fallback);
  return Math.max(min, Math.min(max, parsed));
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

function parseString(value, fallback = "") {
  if (typeof value !== "string") {
    return fallback;
  }
  const normalized = value.trim();
  return normalized || fallback;
}

const authUsername = parseString(process.env.AUTH_USERNAME, "");
const authPassword = parseString(process.env.AUTH_PASSWORD, "");
const jwtSecret = parseString(process.env.JWT_SECRET, "");
const refreshTokenSecret = parseString(process.env.REFRESH_TOKEN_SECRET, jwtSecret);

const config = {
  port: parsePositiveInt(process.env.PORT, 8787),
  host: process.env.HOST || "127.0.0.1",
  apiKey: process.env.API_KEY || "",
  authUsername,
  authPassword,
  jwtSecret,
  refreshTokenSecret,
  jwtExpiresIn: parseString(process.env.JWT_EXPIRES_IN, "15m"),
  refreshTokenExpiresIn: parseString(process.env.REFRESH_TOKEN_EXPIRES_IN, "7d"),
  jwtIssuer: parseString(process.env.JWT_ISSUER, "chromium-fleet-api"),
  jwtAudience: parseString(process.env.JWT_AUDIENCE, "chromium-fleet-clients"),
  disableAuth: parseBoolean(process.env.DISABLE_AUTH, false),
  allowApiKeyAuth: parseBoolean(process.env.ALLOW_API_KEY_AUTH, false),
  allowInstall: parseBoolean(process.env.ALLOW_INSTALL, true),
  allowUninstall: parseBoolean(process.env.ALLOW_UNINSTALL, true),
  allowActions: parseBoolean(process.env.ALLOW_ACTIONS, true),
  commandTimeoutMs: parsePositiveInt(process.env.COMMAND_TIMEOUT_MS, 15 * 60 * 1000),
  sellerRoot: process.env.SELLER_ROOT || "/opt",
  fleetRoot: process.env.FLEET_ROOT || path.resolve(__dirname, "..", ".."),
  corsOrigins: parseOrigins(process.env.CORS_ORIGINS),
  sessionsFile: parseString(process.env.SESSIONS_FILE, "/opt/chromium-fleet-sessions.json"),
  rateLimitAuthWindowMs: parsePositiveInt(process.env.RATE_LIMIT_AUTH_WINDOW_MS || process.env.RATE_LIMIT_WINDOW_MS, 15 * 60 * 1000),
  rateLimitAuthMax: parsePositiveInt(process.env.RATE_LIMIT_AUTH_MAX || process.env.RATE_LIMIT_MAX, 20),
  rateLimitApiWindowMs: parsePositiveInt(process.env.RATE_LIMIT_API_WINDOW_MS, 60 * 1000),
  rateLimitApiMax: parsePositiveInt(process.env.RATE_LIMIT_API_MAX, 200),
  sseMaxConnectionsPerIp: parsePositiveInt(process.env.SSE_MAX_CONNECTIONS_PER_IP, 3),
  sseMaxEventBytes: parsePositiveInt(process.env.SSE_MAX_EVENT_BYTES, 2 * 1024 * 1024),
  sseMaxBytesPerHour: parsePositiveInt(process.env.SSE_MAX_BYTES_PER_HOUR, 100 * 1024 * 1024),
  webhookUrl: parseString(process.env.WEBHOOK_URL, ""),
  monitorCacheTtlMs: clampPositiveInt(process.env.MONITOR_CACHE_TTL_MS, 500, 60_000, 4_000),
  monitorStreamDefaultIntervalMs: clampPositiveInt(
    process.env.MONITOR_STREAM_DEFAULT_INTERVAL_MS,
    2_000,
    120_000,
    15_000
  ),
  monitorStreamMinIntervalMs: clampPositiveInt(
    process.env.MONITOR_STREAM_MIN_INTERVAL_MS,
    2_000,
    120_000,
    5_000
  ),
  monitorStreamMaxIntervalMs: clampPositiveInt(
    process.env.MONITOR_STREAM_MAX_INTERVAL_MS,
    2_000,
    180_000,
    60_000
  ),
  monitorStreamHeartbeatMs: clampPositiveInt(
    process.env.MONITOR_STREAM_HEARTBEAT_MS,
    2_000,
    120_000,
    15_000
  )
};

module.exports = { config };
