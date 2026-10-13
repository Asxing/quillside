import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
    handle,
    createRuntime,
    legacyProvider,
    safeError,
} from "../runtime.mjs";
async function fixture(fn) {
    const directory = await mkdtemp(join(tmpdir(), "quillside-pi-test-"));
    try {
        await fn(directory);
    } finally {
        await rm(directory, { recursive: true, force: true });
    }
}
const context = (directory) => ({
    directory,
    signal: new AbortController().signal,
    emit() {},
    prompt() {
        throw new Error("unexpected prompt");
    },
});
test("catalog exposes official ChatGPT and Codex auth without credentials", () =>
    fixture(async (directory) => {
        const c = await handle({ method: "catalog" }, context(directory));
        for (const id of ["openai", "openai-codex", "anthropic", "deepseek"])
            assert.ok(c.providers.find((p) => p.id === id));
        assert.equal(c.providers.find((p) => p.id === "openai").oauth, true);
        assert.ok(c.providers.every((p) => p.credential === null));
        const m = await handle(
            { method: "models", provider: "openai" },
            context(directory),
        );
        assert.ok(m.models.length);
        assert.ok(!JSON.stringify(c).includes("access_token"));
    }));
test("Pi stores API credentials privately and logout removes only that provider", () =>
    fixture(async (directory) => {
        const ctx = context(directory);
        const key = "synthetic-local-key";
        await handle({ method: "saveKey", provider: "openai", key }, ctx);
        await handle({ method: "saveKey", provider: "anthropic", key }, ctx);
        assert.equal(
            (await stat(join(directory, "auth.json"))).mode & 0o777,
            0o600,
        );
        assert.equal(
            (await handle({ method: "catalog" }, ctx)).providers.find(
                (p) => p.id === "openai",
            ).credential,
            "api_key",
        );
        await handle({ method: "logout", provider: "openai" }, ctx);
        const stored = JSON.parse(
            await readFile(join(directory, "auth.json"), "utf8"),
        );
        assert.equal(stored.openai, undefined);
        assert.equal(stored.anthropic.type, "api_key");
        assert.throws(() =>
            legacyProvider({
                api: "responses",
                baseURL: "http://remote.invalid/v1",
                model: "fixture",
            }),
        );
        await assert.rejects(
            handle(
                {
                    method: "saveKey",
                    provider: "openai",
                    key: "!echo anything",
                },
                ctx,
            ),
        );
    }));
test("real Pi Agent streams through compatibility provider with no tools", () =>
    fixture(async (directory) => {
        let payload;
        const server = createServer(async (req, res) => {
            let body = "";
            for await (const b of req) body += b;
            payload = JSON.parse(body);
            res.writeHead(200, { "Content-Type": "text/event-stream" });
            for (const value of [
                {
                    choices: [
                        {
                            index: 0,
                            delta: { role: "assistant", content: "候选" },
                            finish_reason: null,
                        },
                    ],
                },
                {
                    choices: [
                        {
                            index: 0,
                            delta: { content: "正文" },
                            finish_reason: null,
                        },
                    ],
                },
                { choices: [{ index: 0, delta: {}, finish_reason: "stop" }] },
            ])
                res.write("data: " + JSON.stringify(value) + "\n\n");
            res.end("data: [DONE]\n\n");
        });
        await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
        const ctx = context(directory),
            events = [];
        ctx.emit = (e) => events.push(e);
        try {
            const r = await handle(
                {
                    method: "generate",
                    connection: {
                        api: "chatCompletions",
                        baseURL:
                            "http://127.0.0.1:" + server.address().port + "/v1",
                        model: "fixture",
                    },
                    key: "local-fixture",
                    system: "保留事实",
                    user: "原文",
                },
                ctx,
            );
            assert.equal(r.text, "候选正文");
            assert.equal(r.engine, "pi-agent-core");
            assert.equal(
                events
                    .filter((e) => e.type === "delta")
                    .map((e) => e.text)
                    .join(""),
                "候选正文",
            );
            assert.ok(!payload.tools?.length);
            assert.ok(JSON.stringify(payload).includes("保留事实"));
        } finally {
            server.closeAllConnections();
            await new Promise((resolve) => server.close(resolve));
        }
    }));
test("stop aborts a live provider request without producing a candidate", () =>
    fixture(async (directory) => {
        let began;
        const ready = new Promise((r) => (began = r));
        let closed = false;
        const server = createServer((req, res) => {
            res.writeHead(200, { "Content-Type": "text/event-stream" });
            res.write(": waiting\n\n");
            res.on("close", () => (closed = true));
            began();
        });
        await new Promise((r) => server.listen(0, "127.0.0.1", r));
        const ctx = context(directory),
            abort = new AbortController();
        ctx.signal = abort.signal;
        try {
            const work = handle(
                {
                    method: "generate",
                    connection: {
                        api: "chatCompletions",
                        baseURL:
                            "http://127.0.0.1:" + server.address().port + "/v1",
                        model: "fixture",
                    },
                    key: "local-fixture",
                    system: "system",
                    user: "text",
                },
                ctx,
            );
            await ready;
            abort.abort();
            await assert.rejects(work);
            await new Promise((r) => setTimeout(r, 30));
            assert.equal(closed, true);
        } finally {
            server.closeAllConnections();
            await new Promise((r) => server.close(r));
        }
    }));
test("truncated provider output cannot be reported as a full candidate", () =>
    fixture(async (directory) => {
        const server = createServer((req, res) => {
            res.writeHead(200, { "Content-Type": "text/event-stream" });
            res.end(
                "data: " +
                    JSON.stringify({
                        choices: [
                            {
                                index: 0,
                                delta: { content: "partial" },
                                finish_reason: "length",
                            },
                        ],
                    }) +
                    "\n\ndata: [DONE]\n\n",
            );
        });
        await new Promise((r) => server.listen(0, "127.0.0.1", r));
        try {
            await assert.rejects(
                handle(
                    {
                        method: "generate",
                        connection: {
                            api: "chatCompletions",
                            baseURL:
                                "http://127.0.0.1:" +
                                server.address().port +
                                "/v1",
                            model: "fixture",
                        },
                        key: "local-fixture",
                        system: "x",
                        user: "y",
                    },
                    context(directory),
                ),
            );
        } finally {
            server.closeAllConnections();
            await new Promise((r) => server.close(r));
        }
    }));
test("provider exceptions never disclose raw tokens", () => {
    const detail = "auth failed PRIVATE_VALUE";
    assert.ok(
        !JSON.stringify(safeError(new Error(detail))).includes("PRIVATE_VALUE"),
    );
});

test('ChatGPT login delegates PKCE and returns a stable Quillside host identity',()=>fixture(async directory=>{
 const urls=[];
 const ctx=context(directory);ctx.emit=e=>{if(e.type==='auth'&&e.event.type==='auth_url')urls.push(new URL(e.event.url));};ctx.prompt=async()=>{throw new Error('cancelled by test');};
 try {await assert.rejects(handle({method:'login',provider:'openai'},ctx));}
 catch(e){throw e;}
 assert.equal(urls.length,1);assert.equal(urls[0].origin,'https://auth.openai.com');assert.equal(urls[0].searchParams.get('agent_name_hint'),'Quillside');assert.equal(urls[0].searchParams.get('code_challenge_method'),'S256');assert.ok(urls[0].searchParams.get('state'));
 const first=(await readFile(join(directory,'host-id'),'utf8')).trim();await assert.rejects(handle({method:'login',provider:'openai'},ctx));assert.equal(urls[1].searchParams.get('ext_agent_host_id'),'urn:uuid:'+first);assert.notEqual(urls[0].searchParams.get('state'),urls[1].searchParams.get('state'));
 const c=await handle({method:'catalog'},ctx);assert.equal(c.providers.find(p=>p.id==='openai').credential,null);
}));
