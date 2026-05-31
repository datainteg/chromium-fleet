const crypto = require("node:crypto");

const cors = require("cors");
const express = require("express");
const helmet = require("helmet");

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

function readProvidedApiKey(req) {
  const headerValue = req.headers["x-api-key"];
  if (typeof headerValue === "string" && headerValue.trim() !== "") {
    return headerValue.trim();
  }

  const authHeader = req.headers.authorization;
  if (typeof authHeader === "string" && authHeader.startsWith("Bearer ")) {
    return authHeader.slice("Bearer ".length).trim();
  }

  return "";
}

function authMiddleware(req, res, next) {
  if (config.disableAuth) {
    next();
    return;
  }

  if (!config.apiKey) {
    res.status(500).json({
      error: "Server auth misconfigured: API_KEY is missing"
    });
    return;
  }

  const providedKey = readProvidedApiKey(req);
  if (!timingSafeEqual(providedKey, config.apiKey)) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }

  next();
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

app.use("/api", authMiddleware);

app.get("/api/v1/meta", (req, res) => {
  res.json({
    service: "chromium-fleet-api",
    version: "0.1.0",
    authEnabled: !config.disableAuth,
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
