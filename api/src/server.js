const crypto = require("node:crypto");

const cors = require("cors");
const express = require("express");
const helmet = require("helmet");
const jwt = require("jsonwebtoken");
const packageMeta = require("../package.json");

const { config } = require("./config");
const {
  SELLER_ACTIONS,
  createSeller,
  getSellerSummary,
  listSellers,
  removeSeller,
  resumeAllSellers,
  resumeSeller,
  runSellerAction
} = require("./fleetService");
const {
  getFleetUsage,
  getMonitoringOverviewCached,
  getMonitoringOverview,
  getVmUsage
} = require("./monitoringService");

const app = express();
const refreshSessions = new Map();

app.use(helmet({ contentSecurityPolicy: false }));
app.use(express.json({ limit: "1mb" }));

app.use(
  cors({
    origin(origin, callback) {
      // No Origin header means non-browser clients (curl/server-to-server) or
      // same-origin requests that do not require CORS handling.
      if (!origin) {
        callback(null, true);
        return;
      }

      if (config.corsOrigins.length === 0) {
        callback(new Error("CORS_ORIGINS is not configured"));
        return;
      }

      if (config.corsOrigins.includes(origin)) {
        callback(null, true);
        return;
      }

      callback(new Error("Origin not allowed by CORS"));
    }
  })
);

function timingSafeEqual(left, right) {
  const leftBuffer = Buffer.from(String(left || ""), "utf8");
  const rightBuffer = Buffer.from(String(right || ""), "utf8");
  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function readApiKey(req) {
  const headerValue = req.headers["x-api-key"];
  if (typeof headerValue === "string" && headerValue.trim() !== "") {
    return headerValue.trim();
  }
  return "";
}

function readBearerToken(req) {
  const authHeader = req.headers.authorization;
  if (typeof authHeader === "string" && authHeader.startsWith("Bearer ")) {
    const token = authHeader.slice("Bearer ".length).trim();
    return token || "";
  }
  return "";
}

function readRefreshToken(req) {
  const bodyValue = typeof req.body?.refreshToken === "string" ? req.body.refreshToken.trim() : "";
  if (bodyValue) {
    return bodyValue;
  }

  const headerValue = req.headers["x-refresh-token"];
  if (typeof headerValue === "string" && headerValue.trim() !== "") {
    return headerValue.trim();
  }

  return "";
}

function getAuthMode() {
  const jwtConfigured =
    Boolean(config.authUsername) &&
    Boolean(config.authPassword) &&
    Boolean(config.jwtSecret) &&
    Boolean(config.refreshTokenSecret);
  const apiKeyConfigured = Boolean(config.apiKey) && config.allowApiKeyAuth;
  return {
    jwtConfigured,
    apiKeyConfigured
  };
}

function buildAccessToken(subject) {
  return jwt.sign(
    { sub: subject, role: "api-client", tokenType: "access" },
    config.jwtSecret,
    {
      expiresIn: config.jwtExpiresIn,
      issuer: config.jwtIssuer,
      audience: config.jwtAudience
    }
  );
}

function buildRefreshToken(subject, tokenId) {
  return jwt.sign(
    { sub: subject, tokenType: "refresh", jti: tokenId },
    config.refreshTokenSecret,
    {
      expiresIn: config.refreshTokenExpiresIn,
      issuer: config.jwtIssuer,
      audience: config.jwtAudience
    }
  );
}

function readIssuedAtAndExpiry(jwtToken) {
  const decoded = jwt.decode(jwtToken);
  if (!decoded || typeof decoded !== "object") {
    return { issuedAt: null, expiresAt: null, expiresInSeconds: null };
  }

  const issuedAt = Number.isFinite(decoded.iat) ? decoded.iat : null;
  const expiresAt = Number.isFinite(decoded.exp) ? decoded.exp : null;
  const expiresInSeconds =
    issuedAt !== null && expiresAt !== null ? Math.max(0, expiresAt - issuedAt) : null;
  return { issuedAt, expiresAt, expiresInSeconds };
}

function cleanupRefreshSessions() {
  const now = Math.floor(Date.now() / 1000);
  for (const [tokenId, session] of refreshSessions.entries()) {
    if (!session || !Number.isFinite(session.expiresAt) || session.expiresAt <= now) {
      refreshSessions.delete(tokenId);
    }
  }
}

function revokeRefreshToken(tokenId, reason = "revoked") {
  const session = refreshSessions.get(tokenId);
  if (!session) {
    return false;
  }
  session.revoked = true;
  session.revokedAt = Math.floor(Date.now() / 1000);
  session.reason = reason;
  refreshSessions.set(tokenId, session);
  return true;
}

function revokeAllRefreshTokensForSubject(subject, reason = "replaced") {
  for (const [tokenId, session] of refreshSessions.entries()) {
    if (session?.subject === subject && !session.revoked) {
      revokeRefreshToken(tokenId, reason);
    }
  }
}

function rememberRevokedToken(tokenId, subject, issuedAt, expiresAt, reason) {
  if (!Number.isFinite(expiresAt)) {
    return;
  }
  refreshSessions.set(tokenId, {
    tokenId,
    subject,
    issuedAt: Number.isFinite(issuedAt) ? issuedAt : null,
    expiresAt,
    revoked: true,
    revokedAt: Math.floor(Date.now() / 1000),
    reason
  });
}

function issueTokenPair(subject) {
  cleanupRefreshSessions();

  const accessToken = buildAccessToken(subject);
  const refreshTokenId = crypto.randomUUID();
  const refreshToken = buildRefreshToken(subject, refreshTokenId);

  const accessTiming = readIssuedAtAndExpiry(accessToken);
  const refreshTiming = readIssuedAtAndExpiry(refreshToken);

  if (refreshTiming.expiresAt !== null) {
    refreshSessions.set(refreshTokenId, {
      tokenId: refreshTokenId,
      subject,
      issuedAt: refreshTiming.issuedAt,
      expiresAt: refreshTiming.expiresAt,
      revoked: false
    });
  }

  return {
    tokenType: "Bearer",
    accessToken,
    refreshToken,
    accessExpiresInSeconds: accessTiming.expiresInSeconds,
    refreshExpiresInSeconds: refreshTiming.expiresInSeconds
  };
}

function authMiddleware(req, res, next) {
  if (config.disableAuth) {
    next();
    return;
  }

  const authMode = getAuthMode();
  if (!authMode.jwtConfigured && !authMode.apiKeyConfigured) {
    res.status(500).json({
      error: "Server auth misconfigured: set JWT credentials or enable API key auth"
    });
    return;
  }

  const bearerToken = readBearerToken(req);
  if (bearerToken && authMode.jwtConfigured) {
    try {
      const claims = jwt.verify(bearerToken, config.jwtSecret, {
        issuer: config.jwtIssuer,
        audience: config.jwtAudience
      });
      if (!claims || claims.tokenType !== "access") {
        res.status(401).json({ error: "Invalid token type" });
        return;
      }
      req.auth = {
        method: "jwt",
        subject: claims.sub || null
      };
      next();
      return;
    } catch (error) {
      res.status(401).json({ error: "Invalid or expired token" });
      return;
    }
  }

  if (authMode.apiKeyConfigured) {
    const providedKey = readApiKey(req);
    if (timingSafeEqual(providedKey, config.apiKey)) {
      req.auth = {
        method: "apiKey",
        subject: "api-key-client"
      };
      next();
      return;
    }
  }

  if (authMode.jwtConfigured) {
    res.status(401).json({ error: "Unauthorized: Bearer token required" });
    return;
  }

  if (!authMode.apiKeyConfigured) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }

  res.status(401).json({ error: "Unauthorized" });
}

function asyncHandler(handler) {
  return (req, res, next) => {
    Promise.resolve(handler(req, res, next)).catch(next);
  };
}

function parseIntervalMs(value, fallbackMs = 5000) {
  const parsed = Number.parseInt(String(value || ""), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallbackMs;
  }
  return parsed;
}

app.get("/healthz", (req, res) => {
  res.json({
    ok: true,
    service: "chromium-fleet-api"
  });
});

app.post("/api/v1/auth/login", (req, res) => {
  if (config.disableAuth) {
    res.status(400).json({ error: "Auth is disabled on this server" });
    return;
  }

  const authMode = getAuthMode();
  if (!authMode.jwtConfigured) {
    res.status(500).json({
      error: "JWT auth is not configured on this server"
    });
    return;
  }

  const username = typeof req.body?.username === "string" ? req.body.username.trim() : "";
  const password = typeof req.body?.password === "string" ? req.body.password : "";

  if (!timingSafeEqual(username, config.authUsername) || !timingSafeEqual(password, config.authPassword)) {
    res.status(401).json({ error: "Invalid username or password" });
    return;
  }

  revokeAllRefreshTokensForSubject(config.authUsername, "new-login");
  const tokens = issueTokenPair(config.authUsername);
  res.json(tokens);
});

app.post("/api/v1/auth/refresh", (req, res) => {
  if (config.disableAuth) {
    res.status(400).json({ error: "Auth is disabled on this server" });
    return;
  }

  const authMode = getAuthMode();
  if (!authMode.jwtConfigured) {
    res.status(500).json({
      error: "JWT auth is not configured on this server"
    });
    return;
  }

  const refreshToken = readRefreshToken(req);
  if (!refreshToken) {
    res.status(400).json({ error: "refreshToken is required" });
    return;
  }

  let claims;
  try {
    claims = jwt.verify(refreshToken, config.refreshTokenSecret, {
      issuer: config.jwtIssuer,
      audience: config.jwtAudience
    });
  } catch (error) {
    res.status(401).json({ error: "Invalid or expired refresh token" });
    return;
  }

  if (!claims || claims.tokenType !== "refresh" || typeof claims.jti !== "string" || typeof claims.sub !== "string") {
    res.status(401).json({ error: "Invalid refresh token" });
    return;
  }

  cleanupRefreshSessions();
  const session = refreshSessions.get(claims.jti);
  if (session && session.subject !== claims.sub) {
    res.status(401).json({ error: "Invalid refresh token subject" });
    return;
  }
  if (session && session.revoked) {
    res.status(401).json({ error: "Refresh token is revoked" });
    return;
  }

  const now = Math.floor(Date.now() / 1000);
  if (session && Number.isFinite(session.expiresAt) && session.expiresAt <= now) {
    refreshSessions.delete(claims.jti);
    res.status(401).json({ error: "Refresh token is expired" });
    return;
  }

  if (session) {
    revokeRefreshToken(claims.jti, "rotated");
  } else {
    rememberRevokedToken(claims.jti, claims.sub, claims.iat, claims.exp, "rotated");
  }
  const tokens = issueTokenPair(claims.sub);
  res.json(tokens);
});

app.post("/api/v1/auth/logout", (req, res) => {
  if (config.disableAuth) {
    res.status(400).json({ error: "Auth is disabled on this server" });
    return;
  }

  const authMode = getAuthMode();
  if (!authMode.jwtConfigured) {
    res.status(500).json({
      error: "JWT auth is not configured on this server"
    });
    return;
  }

  const refreshToken = readRefreshToken(req);
  if (!refreshToken) {
    res.status(400).json({ error: "refreshToken is required" });
    return;
  }

  try {
    const claims = jwt.verify(refreshToken, config.refreshTokenSecret, {
      issuer: config.jwtIssuer,
      audience: config.jwtAudience
    });
    if (claims && claims.tokenType === "refresh" && typeof claims.jti === "string") {
      if (!revokeRefreshToken(claims.jti, "logout")) {
        rememberRevokedToken(claims.jti, claims.sub, claims.iat, claims.exp, "logout");
      }
    }
  } catch {
    // Keep logout idempotent.
  }

  cleanupRefreshSessions();
  res.json({ loggedOut: true });
});

app.use("/api", authMiddleware);

app.get("/api/v1/meta", (req, res) => {
  const authMode = getAuthMode();
  res.json({
    service: "chromium-fleet-api",
    version: packageMeta.version,
    authEnabled: !config.disableAuth,
    authMode: {
      jwtEnabled: authMode.jwtConfigured,
      apiKeyEnabled: authMode.apiKeyConfigured,
      refreshTokenRotation: authMode.jwtConfigured
    },
    allowInstall: config.allowInstall,
    allowUninstall: config.allowUninstall,
    allowActions: config.allowActions,
    supportedActions: Object.keys(SELLER_ACTIONS),
    monitoringEndpoints: [
      "/api/v1/monitor/overview",
      "/api/v1/monitor/vm",
      "/api/v1/monitor/fleet",
      "/api/v1/monitor/cluster",
      "/api/v1/monitor/stream",
      "/api/v1/status/live"
    ]
  });
});

app.get(
  "/api/v1/monitor/overview",
  asyncHandler(async (req, res) => {
    const overview = await getMonitoringOverviewCached(config.monitorCacheTtlMs);
    res.json(overview);
  })
);

app.get(
  "/api/v1/monitor/vm",
  asyncHandler(async (req, res) => {
    const vm = await getVmUsage();
    res.json({
      timestamp: new Date().toISOString(),
      vm
    });
  })
);

app.get(
  "/api/v1/monitor/fleet",
  asyncHandler(async (req, res) => {
    const fleet = await getFleetUsage();
    res.json({
      timestamp: new Date().toISOString(),
      fleet
    });
  })
);

app.get(
  "/api/v1/monitor/cluster",
  asyncHandler(async (req, res) => {
    const fleet = await getFleetUsage();
    res.json({
      timestamp: new Date().toISOString(),
      cluster: fleet
    });
  })
);

function monitoringStreamHandler(req, res) {
  const minIntervalMs = config.monitorStreamMinIntervalMs;
  const maxIntervalMs = config.monitorStreamMaxIntervalMs;
  const requestedIntervalMs = parseIntervalMs(req.query.intervalMs, config.monitorStreamDefaultIntervalMs);
  const intervalMs = Math.max(minIntervalMs, Math.min(maxIntervalMs, requestedIntervalMs));
  const heartbeatMs = Math.max(2_000, Math.min(config.monitorStreamHeartbeatMs, intervalMs));

  res.status(200);
  res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");
  res.setHeader("X-Accel-Buffering", "no");
  res.setHeader("Access-Control-Allow-Credentials", "true");
  res.write(`retry: ${intervalMs}\n\n`);
  if (typeof res.flushHeaders === "function") {
    res.flushHeaders();
  }

  let closed = false;
  let inFlight = false;

  const writeEvent = (eventName, payload) => {
    if (closed) {
      return;
    }
    res.write(`event: ${eventName}\n`);
    res.write(`data: ${JSON.stringify(payload)}\n\n`);
  };

  const pushOverview = async () => {
    if (closed || inFlight) {
      return;
    }
    inFlight = true;
    try {
      const overview = await getMonitoringOverviewCached(config.monitorCacheTtlMs);
      writeEvent("overview", overview);
    } catch (error) {
      writeEvent("error", {
        timestamp: new Date().toISOString(),
        error: error?.message || "monitor stream failed"
      });
    } finally {
      inFlight = false;
    }
  };

  writeEvent("ready", {
    timestamp: new Date().toISOString(),
    intervalMs,
    heartbeatMs,
    cacheTtlMs: config.monitorCacheTtlMs
  });
  void pushOverview();

  const overviewInterval = setInterval(() => {
    void pushOverview();
  }, intervalMs);

  const heartbeatInterval = setInterval(() => {
    if (!closed) {
      res.write(`: keepalive ${Date.now()}\n\n`);
    }
  }, heartbeatMs);

  req.on("close", () => {
    closed = true;
    clearInterval(overviewInterval);
    clearInterval(heartbeatInterval);
  });
}

app.get("/api/v1/monitor/stream", monitoringStreamHandler);
app.get("/api/v1/status/live", monitoringStreamHandler);

app.get(
  "/api/v1/sellers",
  asyncHandler(async (req, res) => {
    const sellers = await listSellers();
    res.json({ count: sellers.length, sellers });
  })
);

app.get(
  "/api/v1/sellers/:seller",
  asyncHandler(async (req, res) => {
    const seller = await getSellerSummary(req.params.seller);
    res.json(seller);
  })
);

app.post(
  "/api/v1/sellers",
  asyncHandler(async (req, res) => {
    const result = await createSeller(req.body || {});
    res.status(201).json(result);
  })
);

app.delete(
  "/api/v1/sellers/:seller",
  asyncHandler(async (req, res) => {
    const result = await removeSeller(req.params.seller);
    res.json(result);
  })
);

app.post(
  "/api/v1/sellers/:seller/actions/:action",
  asyncHandler(async (req, res) => {
    const { seller, action } = req.params;
    const result = await runSellerAction(seller, action);
    res.json(result);
  })
);

app.post(
  "/api/v1/sellers/:seller/resume",
  asyncHandler(async (req, res) => {
    const result = await resumeSeller(req.params.seller);
    res.json(result);
  })
);

app.post(
  "/api/v1/sellers/resume-all",
  asyncHandler(async (req, res) => {
    const result = await resumeAllSellers();
    res.json(result);
  })
);

app.use((req, res) => {
  res.status(404).json({ error: "Route not found" });
});

app.use((error, req, res, next) => {
  const statusCode = error.statusCode || (error.message === "Origin not allowed by CORS" ? 403 : 500);
  const details = error.details || null;

  res.status(statusCode).json({
    error: error.message || "Internal server error",
    details
  });
});

app.listen(config.port, config.host, () => {
  const authMode = config.disableAuth ? "disabled" : "enabled";
  console.log(`chromium-fleet-api listening on http://${config.host}:${config.port} (auth ${authMode})`);
});
