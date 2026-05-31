const fs = require("node:fs/promises");
const os = require("node:os");

const { runCommand } = require("./exec");
const { listSellers } = require("./fleetService");

function toPercent(used, total) {
  if (!Number.isFinite(used) || !Number.isFinite(total) || total <= 0) {
    return null;
  }
  return Number(((used / total) * 100).toFixed(2));
}

function bytesFromKiB(value) {
  return Number.isFinite(value) ? value * 1024 : null;
}

function toInt(value) {
  const n = Number.parseInt(String(value), 10);
  return Number.isFinite(n) ? n : null;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function readCpuSnapshot() {
  const stat = await fs.readFile("/proc/stat", "utf8");
  const cpuLine = stat.split("\n").find((line) => line.startsWith("cpu "));
  if (!cpuLine) {
    return null;
  }

  const values = cpuLine
    .trim()
    .split(/\s+/)
    .slice(1)
    .map((item) => Number.parseInt(item, 10));

  if (values.some((value) => !Number.isFinite(value))) {
    return null;
  }

  const total = values.reduce((sum, value) => sum + value, 0);
  const idle = (values[3] || 0) + (values[4] || 0);

  return { total, idle };
}

async function readCpuUsagePercent() {
  if (os.platform() !== "linux") {
    return null;
  }

  try {
    const start = await readCpuSnapshot();
    await delay(250);
    const end = await readCpuSnapshot();
    if (!start || !end) {
      return null;
    }

    const totalDelta = end.total - start.total;
    const idleDelta = end.idle - start.idle;
    if (totalDelta <= 0) {
      return null;
    }

    const active = totalDelta - idleDelta;
    return Number(((active / totalDelta) * 100).toFixed(2));
  } catch {
    return null;
  }
}

function parseMemInfo(content) {
  const map = {};
  for (const rawLine of content.split("\n")) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }
    const match = line.match(/^([A-Za-z_()]+):\s+(\d+)/);
    if (match) {
      map[match[1]] = Number.parseInt(match[2], 10);
    }
  }
  return map;
}

async function readSwapStats() {
  if (os.platform() !== "linux") {
    return {
      available: false,
      totalBytes: null,
      usedBytes: null,
      freeBytes: null,
      usedPercent: null
    };
  }

  try {
    const memInfoText = await fs.readFile("/proc/meminfo", "utf8");
    const memInfo = parseMemInfo(memInfoText);
    const swapTotalBytes = bytesFromKiB(memInfo.SwapTotal);
    const swapFreeBytes = bytesFromKiB(memInfo.SwapFree);

    if (!Number.isFinite(swapTotalBytes) || !Number.isFinite(swapFreeBytes)) {
      return {
        available: false,
        totalBytes: null,
        usedBytes: null,
        freeBytes: null,
        usedPercent: null
      };
    }

    const swapUsedBytes = Math.max(0, swapTotalBytes - swapFreeBytes);

    return {
      available: swapTotalBytes > 0,
      totalBytes: swapTotalBytes,
      usedBytes: swapUsedBytes,
      freeBytes: swapFreeBytes,
      usedPercent: toPercent(swapUsedBytes, swapTotalBytes)
    };
  } catch {
    return {
      available: false,
      totalBytes: null,
      usedBytes: null,
      freeBytes: null,
      usedPercent: null
    };
  }
}

async function readDiskRootStats() {
  try {
    const result = await runCommand("df", ["-kP", "/"], {
      allowFailure: true,
      timeoutMs: 10_000
    });

    if (result.code !== 0 || !result.stdout) {
      return null;
    }

    const lines = result.stdout.split("\n").map((line) => line.trim()).filter(Boolean);
    if (lines.length < 2) {
      return null;
    }

    const fields = lines[1].split(/\s+/);
    if (fields.length < 6) {
      return null;
    }

    const totalKiB = toInt(fields[1]);
    const usedKiB = toInt(fields[2]);
    const availableKiB = toInt(fields[3]);
    const usedPercentText = fields[4];
    const mountPoint = fields.slice(5).join(" ");

    const totalBytes = bytesFromKiB(totalKiB);
    const usedBytes = bytesFromKiB(usedKiB);
    const freeBytes = bytesFromKiB(availableKiB);

    return {
      filesystem: fields[0],
      mountPoint,
      totalBytes,
      usedBytes,
      freeBytes,
      usedPercent: toInt(usedPercentText.replace("%", "")) ?? toPercent(usedBytes, totalBytes)
    };
  } catch {
    return null;
  }
}

async function readContainerUsage(containerNames) {
  if (!Array.isArray(containerNames) || containerNames.length === 0) {
    return [];
  }

  try {
    const args = [
      "stats",
      "--no-stream",
      "--format",
      "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}",
      ...containerNames
    ];

    const result = await runCommand("docker", args, {
      allowFailure: true,
      timeoutMs: 15_000
    });

    if (result.code !== 0 || !result.stdout) {
      return [];
    }

    return result.stdout
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const [name, cpuPercent, memUsage, netIO, blockIO] = line.split("|");
        return { containerName: name, cpuPercent, memUsage, netIO, blockIO };
      });
  } catch {
    return [];
  }
}

function buildFleetSummary(sellers) {
  const totalSellers = sellers.length;
  const runningSellers = sellers.filter((seller) => seller.running).length;
  const stoppedSellers = totalSellers - runningSellers;
  const proxyEnabledSellers = sellers.filter((seller) => seller.hasProxy).length;
  const degradedSellers = sellers
    .filter((seller) => seller.containerState !== "running")
    .map((seller) => ({
      seller: seller.seller,
      containerState: seller.containerState
    }));

  const dockerUnavailable = sellers.some((seller) => seller.containerState === "docker-unavailable");

  let health = "healthy";
  if (dockerUnavailable) {
    health = "critical";
  } else if (degradedSellers.length > 0) {
    health = "degraded";
  } else if (totalSellers === 0) {
    health = "empty";
  }

  return {
    health,
    totalSellers,
    runningSellers,
    stoppedSellers,
    proxyEnabledSellers,
    degradedSellers
  };
}

async function getVmUsage() {
  const [cpuUsagePercent, diskRoot, swap] = await Promise.all([
    readCpuUsagePercent(),
    readDiskRootStats(),
    readSwapStats()
  ]);

  const totalMemoryBytes = os.totalmem();
  const freeMemoryBytes = os.freemem();
  const usedMemoryBytes = totalMemoryBytes - freeMemoryBytes;

  return {
    host: os.hostname(),
    platform: os.platform(),
    release: os.release(),
    arch: os.arch(),
    cpuCores: os.cpus().length,
    uptimeSeconds: Math.floor(os.uptime()),
    loadAverage: {
      oneMinute: Number(os.loadavg()[0].toFixed(2)),
      fiveMinutes: Number(os.loadavg()[1].toFixed(2)),
      fifteenMinutes: Number(os.loadavg()[2].toFixed(2))
    },
    cpu: {
      usagePercent: cpuUsagePercent
    },
    memory: {
      totalBytes: totalMemoryBytes,
      usedBytes: usedMemoryBytes,
      freeBytes: freeMemoryBytes,
      usedPercent: toPercent(usedMemoryBytes, totalMemoryBytes)
    },
    swap,
    diskRoot
  };
}

function buildVmHealth(vm) {
  const issues = [];

  if (Number.isFinite(vm.cpu.usagePercent) && vm.cpu.usagePercent >= 95) {
    issues.push(`High CPU usage: ${vm.cpu.usagePercent}%`);
  }
  if (Number.isFinite(vm.memory.usedPercent) && vm.memory.usedPercent >= 92) {
    issues.push(`High memory usage: ${vm.memory.usedPercent}%`);
  }
  if (vm.diskRoot && Number.isFinite(vm.diskRoot.usedPercent) && vm.diskRoot.usedPercent >= 92) {
    issues.push(`High disk usage on /: ${vm.diskRoot.usedPercent}%`);
  }
  if (
    vm.swap &&
    vm.swap.available &&
    Number.isFinite(vm.swap.usedPercent) &&
    vm.swap.usedPercent >= 95
  ) {
    issues.push(`High swap usage: ${vm.swap.usedPercent}%`);
  }

  return {
    healthy: issues.length === 0,
    issues
  };
}

async function getFleetUsage() {
  const sellers = await listSellers();
  const summary = buildFleetSummary(sellers);
  const containerUsage = await readContainerUsage(sellers.map((seller) => seller.containerName));
  return { summary, sellers, containerUsage };
}

async function getMonitoringOverview() {
  const [vm, fleet] = await Promise.all([getVmUsage(), getFleetUsage()]);
  const vmHealth = buildVmHealth(vm);

  const fleetHealthy =
    fleet.summary.health === "healthy" || fleet.summary.health === "empty";

  const overallHealth = vmHealth.healthy && fleetHealthy ? "healthy" : "degraded";

  return {
    timestamp: new Date().toISOString(),
    health: {
      overall: overallHealth,
      vm: vmHealth,
      fleet: {
        healthy: fleetHealthy,
        status: fleet.summary.health,
        degradedSellers: fleet.summary.degradedSellers
      }
    },
    vm,
    fleet
  };
}

module.exports = {
  getVmUsage,
  getFleetUsage,
  getMonitoringOverview
};
