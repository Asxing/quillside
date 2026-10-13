import { createInterface } from "node:readline";
import { handle, safeError } from "./runtime.mjs";
import { registerBunOAuthFlows } from "@earendil-works/pi-ai/bun-oauth";
// Pi deliberately hides OAuth's Node-only modules from generic bundlers.
// Its standalone registration also works in our bundled Node process.
registerBunOAuthFlows();
const directory = process.env.QUILLSIDE_PI_DIR,
    controller = new AbortController();
let started = false,
    finished = false,
    pending;
const emit = (value) => {
    if (!finished) process.stdout.write(JSON.stringify(value) + "\n");
};
const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
function stop() {
    controller.abort();
    pending?.reject(new Error("cancelled"));
    setTimeout(() => process.exit(0), 1500).unref();
}
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
input.on("close", () => {
    if (!finished) stop();
});
input.on("line", (line) => {
    if (Buffer.byteLength(line) > 2000000) {
        stop();
        return;
    }
    let r;
    try {
        r = JSON.parse(line);
    } catch {
        stop();
        return;
    }
    if (r.method === "cancel") {
        stop();
        return;
    }
    if (r.method === "reply" && pending) {
        const p = pending;
        pending = undefined;
        p.resolve(String(r.value || ""));
        return;
    }
    if (started) return;
    started = true;
    if (!directory) {
        emit({ type: "error", code: "runtime", message: "Pi数据目录不可用。" });
        process.exitCode = 1;
        input.close();
        return;
    }
    handle(r, {
        directory,
        signal: controller.signal,
        emit,
        prompt: (p) =>
            new Promise((resolve, reject) => {
                pending = { resolve, reject };
                emit({
                    type: "prompt",
                    prompt: {
                        type: p.type,
                        message: p.message,
                        options: p.options,
                        placeholder: p.placeholder,
                    },
                });
                p.signal?.addEventListener(
                    "abort",
                    () => {
                        if (pending?.resolve === resolve) pending = undefined;
                        reject(new Error("cancelled"));
                        emit({ type: "promptClosed" });
                    },
                    { once: true },
                );
            }),
    })
        .then(
            (result) => emit({ type: "result", result }),
            (error) => emit({ type: "error", ...safeError(error) }),
        )
        .finally(() => {
            finished = true;
            input.close();
            process.stdin.destroy();
            setTimeout(() => process.exit(0), 20);
        });
});
