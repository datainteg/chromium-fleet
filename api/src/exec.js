const { spawn } = require("node:child_process");

function appendWithCap(previous, chunk, maxChars) {
  const next = previous + chunk;
  if (next.length <= maxChars) {
    return next;
  }
  return next.slice(next.length - maxChars);
}

function runCommand(command, args = [], options = {}) {
  const {
    cwd,
    env,
    timeoutMs = 15 * 60 * 1000,
    maxOutputChars = 250_000,
    allowFailure = false
  } = options;

  const startedAt = Date.now();

  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env: env || process.env,
      shell: false
    });

    let stdout = "";
    let stderr = "";
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 5_000).unref();
    }, timeoutMs);

    child.stdout.on("data", (data) => {
      stdout = appendWithCap(stdout, data.toString("utf8"), maxOutputChars);
    });

    child.stderr.on("data", (data) => {
      stderr = appendWithCap(stderr, data.toString("utf8"), maxOutputChars);
    });

    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });

    child.on("close", (code) => {
      clearTimeout(timer);
      const result = {
        command,
        args,
        code: code ?? -1,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        durationMs: Date.now() - startedAt,
        timedOut
      };

      if (!allowFailure && (result.code !== 0 || timedOut)) {
        const error = new Error(`Command failed: ${command} ${args.join(" ")}`);
        error.details = result;
        reject(error);
        return;
      }

      resolve(result);
    });
  });
}

module.exports = { runCommand };
