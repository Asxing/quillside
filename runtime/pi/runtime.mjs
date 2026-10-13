import { Agent } from "@earendil-works/pi-agent-core";
import { ModelRuntime } from "./node_modules/@earendil-works/pi-coding-agent/dist/core/model-runtime.js";
import { AuthStorage } from "./node_modules/@earendil-works/pi-coding-agent/dist/core/auth-storage.js";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
export const PI_VERSION = "1.2.0";
export function legacyProvider(c) {
    const u = new URL(c.baseURL);
    if (
        u.username ||
        u.password ||
        u.search ||
        u.hash ||
        (u.protocol !== "https:" &&
            !(
                u.protocol === "http:" &&
                ["localhost", "127.0.0.1", "[::1]"].includes(u.hostname)
            ))
    )
        throw new Error("invalid_endpoint");
    const api = {
        responses: "openai-responses",
        chatCompletions: "openai-completions",
        anthropic: "anthropic-messages",
        ollama: "openai-completions",
    }[c.api];
    if (!api || !c.model?.trim()) throw new Error("invalid_model");
    return {
        name: c.name || "Existing connection",
        api,
        baseUrl: u.href.replace(/\/$/, "") + (c.api === "ollama" ? "/v1" : ""),
        authHeader: true,
        models: [
            {
                id: c.model,
                name: c.model,
                reasoning: false,
                input: ["text"],
                contextWindow: 200000,
                maxTokens: c.maxOutputTokens || 2048,
                cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
                compat: {
                    supportsStore: false,
                    supportsDeveloperRole: false,
                    maxTokensField: "max_tokens",
                },
            },
        ],
    };
}
export async function createRuntime(directory) {
    await mkdir(directory, { recursive: true, mode: 0o700 });
    const credentials = AuthStorage.create(join(directory, "auth.json"));
    const runtime = await ModelRuntime.create({
        credentials,
        modelsPath: join(directory, "models.json"),
        modelsStorePath: join(directory, "models-store.json"),
        refreshOnCreate: false,
        allowModelNetwork: false,
    });
    return { runtime, credentials };
}
export function safeError(error) {
    const m = String(error?.message || error);
    if (/cancel|abort/i.test(m))
        return { code: "cancelled", message: "操作已停止。" };
    if (/1455|EADDRINUSE/.test(m))
        return {
            code: "login_port",
            message:
                "登录回调端口被占用。请完成或取消其他 Pi/Codex 登录后重试。",
        };
    if (/429|quota|usage.limit|subscription_sharing_usage/i.test(m))
        return {
            code: "quota",
            message: "模型服务额度暂不可用，请检查订阅额度或稍后重试。",
        };
    if (/401|403|auth|credential|api.key|token/i.test(m))
        return {
            code: "auth",
            message: "模型授权不可用或已过期，请重新登录或保存 API Key。",
        };
    if (/model|404/i.test(m))
        return {
            code: "model",
            message: "当前模型不可用，请刷新列表并重新选择。",
        };
    return {
        code: "runtime",
        message: "Pi 未能完成本次操作，原文未改变。请检查模型服务与网络。",
    };
}
export async function handle(r, { directory, signal, emit, prompt }) {
    const { runtime, credentials } = await createRuntime(directory);
    signal.throwIfAborted();
    const provider = r.provider;
    if (r.method === "catalog") {
        const stored = await credentials.list({ signal });
        return {
            version: PI_VERSION,
            providers: runtime
                .getProviders()
                .filter((p) => p.getModels().length)
                .map((p) => ({
                    id: p.id,
                    name:
                        p.id === "openai"
                            ? "OpenAI / ChatGPT"
                            : p.id === "openai-codex"
                              ? "Codex（兼容）"
                              : p.name,
                    oauth: Boolean(p.auth.oauth),
                    apiKey: Boolean(p.auth.apiKey?.login),
                    credential:
                        stored.find((c) => c.providerId === p.id)?.type || null,
                })),
        };
    }
    if (r.method === "models") {
        if (!runtime.getProvider(provider)) throw new Error("invalid_model");
        return {
            models: runtime
                .getModels(provider)
                .filter((m) => m.input.includes("text"))
                .map((m) => ({
                    id: m.id,
                    name: m.name,
                    maxTokens: m.maxTokens,
                })),
        };
    }
    if (r.method === "login") {
        if (!runtime.getProvider(provider)?.auth.oauth)
            throw new Error("unsupported_auth");
        const path = join(directory, "host-id");
        let id;
        try {
            id = (await readFile(path, "utf8")).trim();
        } catch (e) {
            if (e.code !== "ENOENT") throw e;
            id = randomUUID();
            await writeFile(path, id, { flag: "wx", mode: 0o600 });
        }
        await runtime.login(
            provider,
            "oauth",
            {
                signal,
                notify: (event) => emit({ type: "auth", event }),
                prompt,
            },
            { agentName: "Quillside", getDeviceId: () => id, signal },
        );
        return { authenticated: true };
    }
    if (r.method === "saveKey") {
        if (
            !runtime.getProvider(provider)?.auth.apiKey ||
            typeof r.key !== "string" ||
            !r.key.trim() ||
            r.key.length > 16384 ||
            r.key.startsWith("!")
        )
            throw new Error("invalid_credential");
        await credentials.modify(
            provider,
            async () => ({ type: "api_key", key: r.key }),
            { signal },
        );
        return { authenticated: true };
    }
    if (r.method === "logout") {
        await runtime.logout(provider, { signal });
        return { authenticated: false };
    }
    if (r.method !== "generate") throw new Error("invalid_method");
    if (
        typeof r.system !== "string" ||
        typeof r.user !== "string" ||
        Buffer.byteLength(r.system + r.user) > 1000000
    )
        throw new Error("input_too_large");
    let model;
    if (r.connection) {
        runtime.registerProvider(
            "quillside-legacy",
            legacyProvider(r.connection),
        );
        await runtime.setRuntimeApiKey(
            "quillside-legacy",
            r.key || (r.connection.api === "ollama" ? "ollama" : ""),
        );
        model = runtime.getModel("quillside-legacy", r.connection.model);
    } else model = runtime.getModel(provider, r.model);
    if (!model) throw new Error("invalid_model");
    const auth = await runtime.getAuth(model, { signal });
    if (!auth) throw new Error("missing_credential");
    const subscription = auth.source === "OAuth" && model.provider === "openai";
    const agent = new Agent({
        initialState: {
            systemPrompt: r.system,
            model,
            tools: [],
            messages: [],
            thinkingLevel: "off",
        },
        transport: "sse",
        streamFn: (m, ctx, opts) =>
            runtime.streamSimple(m, ctx, {
                ...opts,
                signal: AbortSignal.any([
                    signal,
                    ...(opts?.signal ? [opts.signal] : []),
                ]),
                transport: "sse",
                cacheRetention: "none",
                maxRetries: 0,
                ...(subscription
                    ? {}
                    : {
                          maxTokens: Math.min(
                              r.maxOutputTokens || 2048,
                              m.maxTokens,
                          ),
                      }),
                onPayload: (p) => {
                    if (
                        m.api === "openai-responses" ||
                        m.api === "openai-codex-responses"
                    )
                        p.store = false;
                    if (subscription)
                        for (const k of [
                            "max_output_tokens",
                            "temperature",
                            "top_p",
                            "prompt_cache_retention",
                            "previous_response_id",
                            "background",
                            "conversation",
                            "metadata",
                            "safety_identifier",
                        ])
                            delete p[k];
                    return p;
                },
            }),
    });
    const abort = () => agent.abort();
    signal.addEventListener("abort", abort, { once: true });
    let bytes = 0;
    const unsubscribe = agent.subscribe((e) => {
        if (e.type === "message_update") {
            const u = e.assistantMessageEvent;
            if (u.type === "text_delta") {
                bytes += Buffer.byteLength(u.delta);
                if (bytes > 2000000) {
                    agent.abort();
                    throw new Error("output_too_large");
                }
                emit({ type: "delta", text: u.delta });
            } else if (u.type === "thinking_delta") emit({ type: "progress" });
        }
    });
    try {
        await agent.prompt(r.user);
        signal.throwIfAborted();
        const last = agent.state.messages.findLast(
            (m) => m.role === "assistant",
        );
        if (!last || last.stopReason !== "stop")
            throw new Error(last?.errorMessage || "incomplete_model_response");
        const text = last.content
            .filter((c) => c.type === "text")
            .map((c) => c.text)
            .join("");
        if (!text.trim()) throw new Error("empty_model_response");
        return { text, engine: "pi-agent-core", version: PI_VERSION };
    } finally {
        signal.removeEventListener("abort", abort);
        unsubscribe();
        agent.abort();
        await agent.waitForIdle();
        agent.reset();
    }
}
