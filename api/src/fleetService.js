const fs = require("node:fs/promises");
const path = require("node:path");

const { config } = require("./config");
const { runCommand } = require("./exec");
const {
  isValidCpuLimit,
  isValidPort,
  isValidProxy,
  isValidResourceSize,
  isValidSellerName,
  isValidSubdomain
} = require("./validators");

const INSTALL_SCRIPT = path.join(config.fleetRoot, "install.sh");
const UNINSTALL_SCRIPT = path.join(config.fleetRoot, "uninstall.sh");

const SELLER_ACTIONS = {
  start: "start.sh",
  stop: "stop.sh",
  restart: "restart.sh",
  recreate: "recreate.sh",
  update: "update.sh",
  status: "status.sh",
  "proxy-status": "proxy-status.sh",
  "proxy-rotate": "proxy-rotate.sh"
};

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function readTextIfExists(filePath) {
  try {
    return await fs.readFile(filePath, "utf8");
  } catch {
    return null;
  }
}

async function isPortInUse(port) {
  try {
    const result = await runCommand("ss", ["-tuln"], { allowFailure: true, timeoutMs: 5_000 });
    return result.stdout.split("\n").some(line => line.includes(`:${port} `) || line.includes(`:${port}\n`) || line.endsWith(`:${port}`));
  } catch {
    return false;
  }
}

function parseHostPort(proxyLine) {
  const [host, port] = proxyLine.split(":");
  if (!host || !port) {
    return null;
  }
  return `${host}:${port}`;
}

function parseComposePort(composeText) {
  if (!composeText) {
    return null;
  }

  const match = composeText.match(/-\s*["'](\d+):3000["']/);
  return match ? Number.parseInt(match[1], 10) : null;
}

function parseProxyCount(proxiesText) {
  if (!proxiesText) {
    return 0;
  }
  return proxiesText
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean).length;
}

function buildSellerPaths(seller) {
  const appDir = path.join(config.sellerRoot, `${seller}-browser`);
  return {
    seller,
    appDir,
    composeFile: path.join(appDir, "docker-compose.yml"),
    proxyConfFile: path.join(appDir, "proxy", "proxies.conf"),
    activeProxyFile: path.join(appDir, "proxy", "active.conf"),
    nginxConfigFile: `/etc/nginx/sites-available/${seller}-chrome`,
    containerName: `${seller}-chrome`
  };
}

async function readContainerState(containerName) {
  try {
    const result = await runCommand(
      "docker",
      ["inspect", "--format", "{{.State.Status}}", containerName],
      { allowFailure: true, timeoutMs: 10_000 }
    );

    if (result.code !== 0) {
      return "not-found";
    }

    return result.stdout || "unknown";
  } catch {
    return "docker-unavailable";
  }
}

async function getInstalledSellerNames() {
  try {
    const entries = await fs.readdir(config.sellerRoot, { withFileTypes: true });
    const names = [];

    for (const entry of entries) {
      if (!entry.isDirectory() || !entry.name.endsWith("-browser")) {
        continue;
      }
      const seller = entry.name.slice(0, -8);
      if (!isValidSellerName(seller)) {
        continue;
      }

      const composeFile = path.join(config.sellerRoot, entry.name, "docker-compose.yml");
      if (await fileExists(composeFile)) {
        names.push(seller);
      }
    }

    return names.sort();
  } catch {
    return [];
  }
}

async function getSellerSummary(seller) {
  if (!isValidSellerName(seller)) {
    const error = new Error("Invalid seller name");
    error.statusCode = 400;
    throw error;
  }

  const sellerPaths = buildSellerPaths(seller);
  const composeText = await readTextIfExists(sellerPaths.composeFile);
  if (!composeText) {
    const error = new Error("Seller not found");
    error.statusCode = 404;
    throw error;
  }

  const [proxyConfText, activeProxyText, containerState] = await Promise.all([
    readTextIfExists(sellerPaths.proxyConfFile),
    readTextIfExists(sellerPaths.activeProxyFile),
    readContainerState(sellerPaths.containerName)
  ]);

  const activeProxy = parseHostPort((activeProxyText || "").trim());
  const proxyCount = parseProxyCount(proxyConfText);

  return {
    seller,
    appDir: sellerPaths.appDir,
    containerName: sellerPaths.containerName,
    port: parseComposePort(composeText),
    containerState,
    running: containerState === "running",
    hasProxy: proxyCount > 0,
    proxyCount,
    activeProxy
  };
}

async function listSellers() {
  const sellerNames = await getInstalledSellerNames();
  const results = await Promise.allSettled(sellerNames.map(name => getSellerSummary(name)));
  return results.filter(r => r.status === "fulfilled").map(r => r.value);
}

function normalizeString(value) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim();
}

function pushOptionalArg(args, flag, value) {
  const normalized = normalizeString(value);
  if (normalized) {
    args.push(flag, normalized);
  }
}

function validateInstallPayload(payload) {
  const seller = normalizeString(payload.seller);
  const pass = normalizeString(payload.pass);
  const subdomain = normalizeString(payload.subdomain);

  if (!isValidSellerName(seller)) {
    throw Object.assign(new Error("seller is required and must match ^[a-z0-9][a-z0-9_-]{0,31}$"), { statusCode: 400 });
  }
  if (!pass) {
    throw Object.assign(new Error("pass is required"), { statusCode: 400 });
  }
  if (!isValidSubdomain(subdomain)) {
    throw Object.assign(
      new Error("subdomain is required and must be a valid domain like chrome1.example.com"),
      { statusCode: 400 }
    );
  }

  if (payload.port !== undefined && !isValidPort(payload.port)) {
    throw Object.assign(new Error("port must be between 1 and 65535"), { statusCode: 400 });
  }
  if (payload.mem !== undefined && !isValidResourceSize(payload.mem)) {
    throw Object.assign(new Error("mem must look like 2g, 1536m, or 1gb"), { statusCode: 400 });
  }
  if (payload.shm !== undefined && !isValidResourceSize(payload.shm)) {
    throw Object.assign(new Error("shm must look like 1gb or 512m"), { statusCode: 400 });
  }
  if (payload.swap !== undefined && !isValidResourceSize(payload.swap)) {
    throw Object.assign(new Error("swap must look like 2G or 4096M"), { statusCode: 400 });
  }
  if (payload.cpu !== undefined && !isValidCpuLimit(payload.cpu)) {
    throw Object.assign(new Error("cpu must be a positive number up to 8"), { statusCode: 400 });
  }

  const proxies = Array.isArray(payload.proxies) ? payload.proxies : [];
  for (const proxy of proxies) {
    if (!isValidProxy(proxy)) {
      throw Object.assign(
        new Error(`invalid proxy '${proxy}' (expected host:port:user:pass)`),
        { statusCode: 400 }
      );
    }
  }

  return {
    seller,
    pass,
    subdomain,
    port: payload.port,
    user: payload.user,
    tz: payload.tz,
    mem: payload.mem,
    cpu: payload.cpu,
    shm: payload.shm,
    swap: payload.swap,
    proxies
  };
}

async function createSeller(payload) {
  if (!config.allowInstall) {
    const error = new Error("Seller creation is disabled by server configuration");
    error.statusCode = 403;
    throw error;
  }

  const input = validateInstallPayload(payload);

  if (input.port && await isPortInUse(input.port)) {
    const error = new Error(`Port ${input.port} is already in use on this host`);
    error.statusCode = 409;
    throw error;
  }

  const args = [
    INSTALL_SCRIPT,
    "--seller", input.seller,
    "--pass", input.pass,
    "--subdomain", input.subdomain
  ];

  pushOptionalArg(args, "--port", input.port);
  pushOptionalArg(args, "--user", input.user);
  pushOptionalArg(args, "--tz", input.tz);
  pushOptionalArg(args, "--mem", input.mem);
  pushOptionalArg(args, "--cpu", input.cpu);
  pushOptionalArg(args, "--shm", input.shm);
  pushOptionalArg(args, "--swap", input.swap);

  for (const proxy of input.proxies) {
    args.push("--proxy", proxy);
  }

  const result = await runCommand("bash", args, {
    cwd: config.fleetRoot,
    timeoutMs: config.commandTimeoutMs
  });

  return {
    seller: input.seller,
    result
  };
}

async function removeSeller(seller) {
  if (!config.allowUninstall) {
    const error = new Error("Seller uninstall is disabled by server configuration");
    error.statusCode = 403;
    throw error;
  }

  if (!isValidSellerName(seller)) {
    const error = new Error("Invalid seller name");
    error.statusCode = 400;
    throw error;
  }

  const result = await runCommand("bash", [UNINSTALL_SCRIPT, "--seller", seller, "--yes"], {
    cwd: config.fleetRoot,
    timeoutMs: config.commandTimeoutMs
  });

  return { seller, result };
}

async function runSellerAction(seller, action) {
  if (!config.allowActions) {
    const error = new Error("Seller actions are disabled by server configuration");
    error.statusCode = 403;
    throw error;
  }

  if (!isValidSellerName(seller)) {
    const error = new Error("Invalid seller name");
    error.statusCode = 400;
    throw error;
  }

  const scriptName = SELLER_ACTIONS[action];
  if (!scriptName) {
    const error = new Error(`Unsupported action '${action}'`);
    error.statusCode = 400;
    throw error;
  }

  const sellerPaths = buildSellerPaths(seller);
  const scriptPath = path.join(sellerPaths.appDir, scriptName);
  if (!(await fileExists(scriptPath))) {
    const error = new Error(`Action script not found: ${scriptPath}`);
    error.statusCode = 404;
    throw error;
  }

  const result = await runCommand("bash", [scriptPath], {
    cwd: sellerPaths.appDir,
    timeoutMs: config.commandTimeoutMs
  });

  return { seller, action, result };
}

async function resumeSeller(seller) {
  const before = await getSellerSummary(seller);
  if (before.running) {
    return {
      seller,
      resumed: false,
      reason: "already-running",
      before,
      after: before
    };
  }

  const actionResult = await runSellerAction(seller, "start");
  const after = await getSellerSummary(seller);
  return {
    seller,
    resumed: true,
    reason: "started",
    before,
    after,
    result: actionResult.result
  };
}

async function resumeAllSellers() {
  const sellers = await listSellers();
  const results = [];

  for (const seller of sellers) {
    try {
      if (seller.running) {
        results.push({
          seller: seller.seller,
          resumed: false,
          reason: "already-running",
          before: seller,
          after: seller
        });
        continue;
      }

      const actionResult = await runSellerAction(seller.seller, "start");
      const after = await getSellerSummary(seller.seller);
      results.push({
        seller: seller.seller,
        resumed: true,
        reason: "started",
        before: seller,
        after,
        result: actionResult.result
      });
    } catch (error) {
      results.push({
        seller: seller.seller,
        resumed: false,
        reason: "failed",
        error: error.message || "failed to resume seller"
      });
    }
  }

  const resumedCount = results.filter((item) => item.resumed).length;
  const failedCount = results.filter((item) => item.reason === "failed").length;

  return {
    total: results.length,
    resumedCount,
    failedCount,
    results
  };
}

async function listProxies(seller) {
  if (!isValidSellerName(seller)) {
    throw Object.assign(new Error("Invalid seller name"), { statusCode: 400 });
  }
  const sellerPaths = buildSellerPaths(seller);
  const composeText = await readTextIfExists(sellerPaths.composeFile);
  if (!composeText) {
    throw Object.assign(new Error("Seller not found"), { statusCode: 404 });
  }

  const proxyConfText = (await readTextIfExists(sellerPaths.proxyConfFile)) || "";
  const activeProxyText = ((await readTextIfExists(sellerPaths.activeProxyFile)) || "").trim();

  const proxies = proxyConfText
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .map((line, idx) => {
      const parts = line.split(":");
      const host = parts[0] || "";
      const port = parts[1] || "";
      const user = parts[2] || "";
      const active = Boolean(activeProxyText && activeProxyText.startsWith(`${host}:${port}:`));
      return { index: idx, host, port, user, active };
    });

  return { seller, count: proxies.length, proxies };
}

async function addProxy(seller, proxyLine) {
  if (!isValidSellerName(seller)) {
    throw Object.assign(new Error("Invalid seller name"), { statusCode: 400 });
  }
  if (!isValidProxy(proxyLine)) {
    throw Object.assign(
      new Error("Invalid proxy format. Expected: host:port:user:pass with a numeric port"),
      { statusCode: 400 }
    );
  }

  const sellerPaths = buildSellerPaths(seller);
  const composeText = await readTextIfExists(sellerPaths.composeFile);
  if (!composeText) {
    throw Object.assign(new Error("Seller not found"), { statusCode: 404 });
  }

  const current = (await readTextIfExists(sellerPaths.proxyConfFile)) || "";
  const lines = current
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);

  const [newHost, newPort] = proxyLine.split(":");
  if (lines.some((l) => l.startsWith(`${newHost}:${newPort}:`))) {
    throw Object.assign(new Error("Proxy already exists in pool"), { statusCode: 409 });
  }

  await fs.mkdir(path.dirname(sellerPaths.proxyConfFile), { recursive: true });
  const updated = [...lines, proxyLine];
  await fs.writeFile(sellerPaths.proxyConfFile, updated.join("\n") + "\n", "utf8");
  await fs.chmod(sellerPaths.proxyConfFile, 0o600);

  return {
    seller,
    added: `${newHost}:${newPort}`,
    count: updated.length
  };
}

async function removeProxy(seller, indexParam) {
  if (!isValidSellerName(seller)) {
    throw Object.assign(new Error("Invalid seller name"), { statusCode: 400 });
  }

  const sellerPaths = buildSellerPaths(seller);
  const composeText = await readTextIfExists(sellerPaths.composeFile);
  if (!composeText) {
    throw Object.assign(new Error("Seller not found"), { statusCode: 404 });
  }

  const current = (await readTextIfExists(sellerPaths.proxyConfFile)) || "";
  const lines = current
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);

  const idx = Number.parseInt(String(indexParam), 10);
  if (!Number.isFinite(idx) || idx < 0 || idx >= lines.length) {
    const range = lines.length > 0 ? `0–${lines.length - 1}` : "empty";
    throw Object.assign(
      new Error(`Proxy index ${indexParam} out of range (${range})`),
      { statusCode: 400 }
    );
  }

  const removed = lines[idx];
  const [removedHost, removedPort] = removed.split(":");
  lines.splice(idx, 1);

  await fs.writeFile(
    sellerPaths.proxyConfFile,
    lines.length > 0 ? lines.join("\n") + "\n" : "",
    "utf8"
  );

  // If the removed proxy was active, clear active.conf so health cron picks a new one
  const activeProxyText = ((await readTextIfExists(sellerPaths.activeProxyFile)) || "").trim();
  if (activeProxyText.startsWith(`${removedHost}:${removedPort}:`)) {
    await fs.writeFile(sellerPaths.activeProxyFile, "", "utf8").catch(() => {});
  }

  return {
    seller,
    removed: `${removedHost}:${removedPort}`,
    count: lines.length
  };
}

async function getSellerLogs(seller, lines = 100) {
  if (!isValidSellerName(seller)) {
    throw Object.assign(new Error("Invalid seller name"), { statusCode: 400 });
  }
  const n = Math.min(Math.max(1, Number.parseInt(String(lines), 10) || 100), 1000);
  const sellerPaths = buildSellerPaths(seller);
  const composeText = await readTextIfExists(sellerPaths.composeFile);
  if (!composeText) {
    throw Object.assign(new Error("Seller not found"), { statusCode: 404 });
  }
  const result = await runCommand(
    "docker",
    ["logs", "--tail", String(n), "--timestamps", sellerPaths.containerName],
    { allowFailure: true, timeoutMs: 15_000 }
  );
  return {
    seller,
    containerName: sellerPaths.containerName,
    lines: n,
    logs: (result.stderr || result.stdout || "").trim()
  };
}

async function testSellerProxies(seller) {
  if (!isValidSellerName(seller)) {
    throw Object.assign(new Error("Invalid seller name"), { statusCode: 400 });
  }
  const sellerPaths = buildSellerPaths(seller);
  const composeText = await readTextIfExists(sellerPaths.composeFile);
  if (!composeText) {
    throw Object.assign(new Error("Seller not found"), { statusCode: 404 });
  }

  const proxyConfText = (await readTextIfExists(sellerPaths.proxyConfFile)) || "";
  const rawLines = proxyConfText.split("\n").map(l => l.trim()).filter(Boolean);

  if (rawLines.length === 0) {
    return { seller, count: 0, proxies: [] };
  }

  const activeProxyText = ((await readTextIfExists(sellerPaths.activeProxyFile)) || "").trim();

  const proxies = await Promise.all(
    rawLines.map(async (line, idx) => {
      const [host, port, user, pass] = line.split(":");
      const startMs = Date.now();
      try {
        const result = await runCommand(
          "curl",
          ["-fsSL", "--max-time", "5", "--proxy", `http://${user}:${pass}@${host}:${port}`, "https://api.ipify.org"],
          { allowFailure: true, timeoutMs: 8_000 }
        );
        const alive = result.code === 0;
        return {
          index: idx,
          host,
          port,
          user,
          alive,
          latencyMs: alive ? Date.now() - startMs : null,
          externalIp: alive ? result.stdout.trim() : null,
          active: Boolean(activeProxyText && activeProxyText.startsWith(`${host}:${port}:`))
        };
      } catch {
        return { index: idx, host, port, user, alive: false, latencyMs: null, externalIp: null, active: false };
      }
    })
  );

  return { seller, count: proxies.length, proxies };
}

module.exports = {
  listSellers,
  getSellerSummary,
  createSeller,
  removeSeller,
  runSellerAction,
  resumeSeller,
  resumeAllSellers,
  listProxies,
  addProxy,
  removeProxy,
  getSellerLogs,
  testSellerProxies,
  SELLER_ACTIONS
};
