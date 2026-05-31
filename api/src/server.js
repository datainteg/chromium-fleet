const crypto = require("node:crypto");

const cors = require("cors");
const express = require("express");
const helmet = require("helmet");
const jwt = require("jsonwebtoken");

const { config } = require("./config");
const {
  SELLER_ACTIONS,
  createSeller,
  getSellerSummary,
  listSellers,
  removeSeller,
  runSellerAction
} = require("./fleetService");
const {
  getFleetUsage,
  getMonitoringOverview,
  getVmUsage
} = require("./monitoringService");

const app = express();

app.use(helmet({ contentSecurityPolicy: false }));
app.use(express.json({ limit: "1mb" }));

if (config.corsOrigins.length > 0) {
  app.use(
    cors({
      origin(origin, callback) {
        if (!origin || config.corsOrigins.includes(origin)) {
          callback(null, true);
          return;
        }
        callback(new Error("Origin not allowed by CORS"));
      }
    })
  );
} else {
  app.use(cors());
}

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

function getAuthMode() {
  const jwtConfigured =
    Boolean(config.authUsername) &&
    Boolean(config.authPassword) &&
    Boolean(config.jwtSecret);
  const apiKeyConfigured = Boolean(config.apiKey) && config.allowApiKeyAuth;
  return {
    jwtConfigured,
    apiKeyConfigured
  };
}

function buildAccessToken(subject) {
  return jwt.sign(
    { sub: subject, role: "api-client" },
    config.jwtSecret,
    {
      expiresIn: config.jwtExpiresIn,
      issuer: config.jwtIssuer,
      audience: config.jwtAudience
    }
  );
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

  const accessToken = buildAccessToken(config.authUsername);
  const decoded = jwt.decode(accessToken);
  const expiresInSeconds =
    decoded && typeof decoded === "object" && decoded.exp && decoded.iat
      ? Math.max(0, decoded.exp - decoded.iat)
      : null;

  res.json({
    tokenType: "Bearer",
    accessToken,
    expiresInSeconds
  });
});

app.use("/api", authMiddleware);

app.get("/api/v1/meta", (req, res) => {
  const authMode = getAuthMode();
  res.json({
    service: "chromium-fleet-api",
    version: "0.2.0",
    authEnabled: !config.disableAuth,
    authMode: {
      jwtEnabled: authMode.jwtConfigured,
      apiKeyEnabled: authMode.apiKeyConfigured
    },
    allowInstall: config.allowInstall,
    allowUninstall: config.allowUninstall,
    allowActions: config.allowActions,
    supportedActions: Object.keys(SELLER_ACTIONS),
    monitoringEndpoints: [
      "/api/v1/monitor/overview",
      "/api/v1/monitor/vm",
      "/api/v1/monitor/fleet",
      "/api/v1/monitor/cluster"
    ]
  });
});

app.get(
  "/api/v1/monitor/overview",
  asyncHandler(async (req, res) => {
    const overview = await getMonitoringOverview();
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
