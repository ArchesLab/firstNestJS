# Redis Call-Return APIs in TypeScript/Node.js — A CPC-Oriented Analysis Reference

This document catalogs the Redis call-return APIs that a static analyzer must recognize in order to reconstruct **Component-Port-Connector (CPC)** architectures from TypeScript/NestJS microservices, and maps each API to the Axios primitives that the existing analysis already handles.

**Scope note.** Only **call-return / request-response** styles are covered. Redis Pub/Sub (`publish`, `subscribe`, `psubscribe`, `on('message', ...)`) is **explicitly excluded** per the assignment. Note that NestJS's Redis microservice transport uses Redis pub/sub channels under the hood, but its `@MessagePattern` programming model is synchronous request-response at the API surface and is therefore in scope.

## 1. Two Call-Return Variants

| Variant | Call-return semantics | Library |
| --- | --- | --- |
| **Direct Redis commands** | Every command (`GET`, `SET`, `HGET`, `LPUSH`, `EVAL`, ...) returns `Promise<T>` | `ioredis`, `redis` (node-redis v4+) |
| **NestJS Redis microservice (RPC)** | `client.send(pattern, payload)` → `Observable<Response>` | `@nestjs/microservices` with `Transport.REDIS` |

Each variant is covered separately because the CPC primitives map differently.

---

## 2. Variant 1 — Direct Redis Commands

### 2.1 Connection / Client Identity

Both libraries identify a Redis server instance by `host`+`port` (+ optional `db`, `password`, `tls`). This is the **Component Instance Identity** — the analogue of Axios's `baseURL`.

**ioredis** — [github.com/redis/ioredis](https://github.com/redis/ioredis):

```typescript
import Redis from 'ioredis';

new Redis();                                                // 127.0.0.1:6379
new Redis(6380);                                            // port only
new Redis(6379, '192.168.1.1');                             // port + host
new Redis({ host: '127.0.0.1', port: 6379, password: 'x', db: 0 });
new Redis('redis://:auth@127.0.0.1:6380/4');                // URL
new Redis('rediss://user:pass@host:port/db');               // TLS
```

**node-redis v4+** (`redis` package):

```typescript
import { createClient, RedisClientType } from 'redis';

const client: RedisClientType = createClient({
  url: 'redis://alice:pw@redis.example:6380',
});
await client.connect();
```

### 2.2 Call-Return Commands

Each command is a single call-return roundtrip. The payload is a key (string) plus arguments; the response is the command's return value.

| Operation | ioredis (lowercase) | node-redis v4+ (camelCase) |
| --- | --- | --- |
| String | `redis.get(key)` / `redis.set(key, value)` | `client.get(key)` / `client.set(key, value)` |
| String w/ TTL | `redis.set(k, v, 'EX', 10)` | `client.set(k, v, { EX: 10 })` |
| Hash | `redis.hset`, `redis.hget`, `redis.hgetall` | `client.hSet`, `client.hGet`, `client.hGetAll` |
| Counter | `redis.incr(k)` / `redis.decr(k)` | `client.incr(k)` / `client.decr(k)` |
| List | `redis.lpush`, `redis.lrange` | `client.lPush`, `client.lRange` |
| Sorted set | `redis.zadd('z', 1, 'one')` | `client.zAdd('z', { score: 1, value: 'one' })` |
| Scripting | `redis.eval(script, numKeys, ...)`, `redis.call('CMD', ...args)` | `client.eval(script, { keys, arguments })`, `client.sendCommand([...])` |

Batched call-return:

```typescript
const results = await redis.multi().set('foo', 'bar').get('foo').exec();
await redis.pipeline().set('k', 'v').incr('c').exec();
const [setReply, other] = await client.multi().set('key', 'v').get('other').exec();
```

### 2.3 Typical NestJS Wiring

```typescript
import Redis from 'ioredis';
import { ConfigService } from '@nestjs/config';

@Module({
  providers: [{
    provide: 'REDIS_CLIENT',
    useFactory: (cfg: ConfigService) => new Redis({
      host: cfg.get<string>('REDIS_HOST'),
      port: cfg.get<number>('REDIS_PORT'),
      password: cfg.get<string>('REDIS_PASSWORD'),
    }),
    inject: [ConfigService],
  }],
  exports: ['REDIS_CLIENT'],
})
export class RedisModule {}

@Injectable()
export class CacheService {
  constructor(@Inject('REDIS_CLIENT') private redis: Redis) {}
  getUser(id: number) { return this.redis.get(`user:${id}`); }
}
```

Note the ConfigService-driven host/port pattern — it is the same pattern the existing Axios analysis already handles for `*_SERVICE_URL`.

### 2.4 CPC Mapping (Direct Commands)

| CPC concept | Direct-Redis construct |
| --- | --- |
| **Component Type Identity** | The Redis server itself (datastore). Not a NestJS microservice, but a shared infra component |
| **Component Instance Identity** | `host:port` (+ db) in `new Redis({...})` / `createClient({ url })` |
| **Provider Port** | The Redis server exposing the full command set on a connection (modeled per-server, not per-key) |
| **Requirer Port** | The injected client (`@Inject('REDIS_CLIENT') redis: Redis`) |
| **Port Type** | The Redis **key name** (`user:42`, `cart:session:x`) + the command verb (`GET`, `HSET`) |
| **Message Type** | Command arguments + value schema. Values are typically `JSON.stringify(obj: T)` on write and parsed back on read |
| **Connector** | TCP/TLS socket to the Redis server; implicit (synthesized by the analyzer) |

### 2.5 AST Constructs to Detect

1. **Import**: `import Redis from 'ioredis'` (or `import * as Redis from 'ioredis'`), `import { createClient } from 'redis'`.
2. **Construction**:
   - `new Redis(...)`, `new Redis.Cluster(...)`, `createClient({...})`.
   - First positional arg may be a port (`number`), host (`string`), or URL (`string`); alternatively an `ObjectExpression` with `host` / `port` / `url`.
   - If the arg references `ConfigService.get('REDIS_HOST' | 'REDIS_PORT' | 'REDIS_URL')`, reuse the existing URL-resolution data flow.
3. **DI binding**: `@Module({ providers: [{ provide: 'REDIS_CLIENT', useFactory: ... }] })` and matching `@Inject('REDIS_CLIENT')` constructor parameters. The string token is the **binding id**.
4. **Call sites**: `MemberExpression` `redis.<cmd>(key, ...)` where `<cmd>` is a member of the Redis command set. First argument = key (Port Type); remaining = payload. Also `redis.multi().x().y().exec()` chains and `redis.pipeline()`.
5. **Script/raw**: `redis.eval(script, ...)`, `redis.call('CMD', ...)`, `client.sendCommand([...])`.

---

## 3. Variant 2 — NestJS Redis Microservice (RPC)

Per the [NestJS Redis docs](https://docs.nestjs.com/microservices/redis), Nest's Redis transporter uses pub/sub channels beneath, but on the client side `client.send(pattern, payload)` returns `Observable<Response>` — a **synchronous RPC call-return** at the API surface.

### 3.1 Provider (Server) Side

```typescript
// main.ts
const app = await NestFactory.createMicroservice<MicroserviceOptions>(AppModule, {
  transport: Transport.REDIS,
  options: { host: 'localhost', port: 6379 },
});

// math.controller.ts
interface SumDto { values: number[] }

@Controller()
export class MathController {
  @MessagePattern({ cmd: 'sum' })
  sum(@Payload() data: SumDto): number {
    return data.values.reduce((a, b) => a + b, 0);
  }
}
```

### 3.2 Requirer (Client) Side

```typescript
@Module({
  imports: [
    ClientsModule.registerAsync([{
      name: 'MATH_SERVICE',
      imports: [ConfigModule],
      useFactory: (cfg: ConfigService) => ({
        transport: Transport.REDIS,
        options: { host: cfg.get('REDIS_HOST'), port: cfg.get<number>('REDIS_PORT') },
      }),
      inject: [ConfigService],
    }]),
  ],
})
export class AppModule {}

@Injectable()
export class MathService {
  constructor(@Inject('MATH_SERVICE') private client: ClientProxy) {}
  sum(values: number[]): Promise<number> {
    return firstValueFrom(this.client.send<number, SumDto>({ cmd: 'sum' }, { values }));
  }
}
```

### 3.3 `@MessagePattern` vs `@EventPattern`

| | `@MessagePattern` | `@EventPattern` |
| --- | --- | --- |
| Programming model | **Request-response (RPC, in scope)** | Fire-and-forget event (out of scope) |
| Client call | `client.send(pattern, payload)` → `Observable<Response>` | `client.emit(pattern, payload)` → `Observable<void>` |
| Server return | Serialized back as reply | Ignored |

A static analyzer must distinguish the two by decorator name.

### 3.4 CPC Mapping (NestJS Redis RPC)

| CPC concept | NestJS Redis RPC construct |
| --- | --- |
| **Component Type Identity** | The NestJS microservice hosting the `@MessagePattern` handlers |
| **Component Instance Identity** | `options.host` + `options.port` (or `options.url`) of the Redis broker — broker address, not callee address |
| **Provider Port** | `@MessagePattern(pattern)` handler in a server controller |
| **Requirer Port** | `@Inject('X_SERVICE') client: ClientProxy` + each `client.send(pattern, ...)` call site |
| **Port Type** | Routing **pattern** string or object: `'sum'`, `{ cmd: 'sum' }` |
| **Message Type** | Request: second arg to `send` / `@Payload()` type. Response: `send<Response, Request>` first generic parameter or handler return type |
| **Connector** | Redis pub/sub reply-channel pair keyed by correlation ID (synthesized by the analyzer) |

### 3.5 AST Constructs to Detect

1. **Server bootstrap**: `NestFactory.createMicroservice(..., { transport: Transport.REDIS, options: { host, port } })` or `app.connectMicroservice(...)`.
2. **Handler**: any `MethodDeclaration` decorated with `@MessagePattern(PATTERN)`. Extract `PATTERN`, `@Payload()` parameter type, and method return type (the reply schema). Distinguish from `@EventPattern` by decorator name.
3. **Client module**: `ClientsModule.register([...])` / `registerAsync([...])` with `transport: Transport.REDIS`. Record the `name` token and extract `options.host/port/url` (including `ConfigService.get(...)` resolution).
4. **Client call site**: `@Inject(NAME) client: ClientProxy` → `client.send(PATTERN, PAYLOAD)` (and any `firstValueFrom` / `lastValueFrom` / `.toPromise()` unwrap). Capture PATTERN (the Port Type), payload type, and generic type arguments `send<TResult, TInput>`.
5. **Alternative client DI**: `@Client({ transport: Transport.REDIS, options: {...} })` property decorator and `ClientProxyFactory.create(...)`.

---

## 4. Mapping Redis ↔ Axios (CPC Primitives)

### 4.1 Direct Commands

| Axios primitive | Direct-Redis counterpart |
| --- | --- |
| `axios.create({ baseURL })` | `new Redis({ host, port })` / `createClient({ url })` |
| HTTP method (GET/POST/PUT/DELETE) | Redis command verb (`GET`, `SET`, `HGET`, `LPUSH`, `ZADD`, ...) |
| URL path `/users/42` | Redis **key name** `users:42` |
| `axios.post('/users', body)` | `redis.set('users:42', JSON.stringify(user))` / `redis.hset('users:42', ...)` |
| Response body | Command return value (`Promise<string \| null \| number \| ...>`) |
| Query params | Extra command arguments (`'EX'`, `10`, `'NX'`) |
| `AxiosResponse<T>` generic | TS generic in `ioredis`'s typed commands / explicit post-parse cast |
| Base URL via `ConfigService.get('X_SERVICE_URL')` | `REDIS_HOST` / `REDIS_PORT` / `REDIS_URL` via `ConfigService` |
| Interceptors | `redis.on('error'/'connect'/...)` (loosely analogous) |

### 4.2 NestJS Redis RPC

| Axios primitive | NestJS-Redis-RPC counterpart |
| --- | --- |
| `axios.create({ baseURL })` | `ClientsModule.register([{ name, transport: Transport.REDIS, options: { host, port } }])` |
| `axios.post('/route', payload)` | `client.send({ cmd: 'route' }, payload)` |
| URL path | **Routing pattern** (string or `{ cmd: ... }` object) |
| HTTP method | *Not applicable* — pattern alone is the route |
| Response `AxiosResponse<T>` | `Observable<T>` → `firstValueFrom(...)` → `Promise<T>` |
| `axios.get` (no body) | `client.send(pattern, undefined)` |
| Server route `@Post('/route')` | `@MessagePattern({ cmd: 'route' })` |
| Server handler `return` | Reply serialized back on Redis reply channel |

---

## 5. Architectural Element ⇨ Code Construct Summary

Same table style as the existing REST/Axios mapping in the project's API-analysis document.

### 5.1 Direct Redis

| Architectural Element | Code Construct / API Signature | Extraction Mechanism / AST Target |
| --- | --- | --- |
| **Component Instance Identity** | `new Redis({host, port})`, `createClient({ url })` | `NewExpression` / `CallExpression` on `createClient`; resolve `host`/`port`/`url` via existing URL-resolution data flow |
| **Requirer Port Creation** | `@Inject('REDIS_CLIENT') private redis: Redis`, provider factory | Parameter decorator + `useFactory` provider metadata |
| **Port Type** | Redis command verb + key-name string literal / template | `MethodCallExpr` on the client; first arg resolves via `resolveExprValue(...)` (template literals, concats, vars) |
| **Message Sending** | `redis.set(key, value)`, `redis.hset(key, field, value)`, ... | `CallExpression` on the client member; value arg is the outbound Message Type |
| **Message Type** | `JSON.stringify(payload: T)` before write; cast on read | Data-flow analysis across `JSON.stringify` / `JSON.parse` boundary |

### 5.2 NestJS Redis RPC

| Architectural Element | Code Construct / API Signature | Extraction Mechanism / AST Target |
| --- | --- | --- |
| **Component Type Identity** | `NestFactory.createMicroservice({ transport: Transport.REDIS, ... })` | Bootstrap `CallExpression` with matching options |
| **Component Instance Identity** | `options.host` + `options.port` (broker address) | Object-literal property extraction + `ConfigService` data flow |
| **Provider Port Creation** | `@MessagePattern(pattern)` | Decorator identifier + argument extraction; reject `@EventPattern` |
| **Requirer Port Creation** | `ClientsModule.register([{ transport: Transport.REDIS, ... }])`, `@Inject('X') client: ClientProxy` | Array-element extraction of module metadata + binding-token match |
| **Port Type** | Routing pattern string or `{ cmd: '...' }` object | String-literal / object-literal argument of `send` / `@MessagePattern` |
| **Message Sending** | `client.send(pattern, payload)` + unwrap (`firstValueFrom`) | `CallExpression` on `ClientProxy` member |
| **Message Type** | Generic args `send<TResult, TInput>`; `@Payload()` type; handler return type | Generic-argument extraction; TS type resolution |

---

## 6. What Changes in the Existing Analysis Pipeline

The existing Axios pipeline is:

1. **CodeQL query** (`dataflow6.ql`) — taint-tracks `ConfigService.get('*_SERVICE_URL')` sources into Axios sinks and resolves the concatenated URL string.
2. **Python orchestrator** (`tests/query.py`) — parses CSV, resolves `{*_SERVICE_URL}` placeholders against `.env` files, deduplicates.
3. **PlantUML generator** (`converter.py`) — renders the architecture diagram.

To lift this to Redis, the **sink** and **port-type extraction** change. The source side (`ConfigService.get('...')`) is identical — Redis hosts, ports, and URLs are injected the same way Axios URLs are. Specifically:

- For **Direct Redis**, replace Axios's `isSink` with a `MethodCallExpr` whose receiver has been identified as a Redis client (via DI binding, `new Redis()`, or `createClient()` construction) and whose method name matches the Redis command set.
- For **NestJS Redis RPC**, add two new sink shapes: (a) `ClientsModule.register([{ transport: Transport.REDIS, options: {...} }])` for Requirer Port creation, and (b) `client.send(pattern, payload)` call sites paired with `@MessagePattern(pattern)` handlers on the provider side.
- The HTTP-method extractor (`httpMethod(sink)`) is replaced by a Redis-specific extractor that returns either (command verb + key) for direct commands, or the routing pattern for NestJS RPC.
- URL resolution (`resolveExprValue`, `resolveTemplateElements`), service identification (`callerService` by file path), env-var substitution in Python, and PlantUML rendering remain unchanged — those protocol-agnostic parts are precisely what the refactor in the companion `STUDENT_GUIDE.md` extracts into a reusable analysis core.

---

## 7. Sources

- [NestJS Redis Microservices docs](https://docs.nestjs.com/microservices/redis)
- [NestJS Microservices Basics (ClientsModule, ClientProxy)](https://docs.nestjs.com/microservices/basics)
- [ioredis — GitHub README](https://github.com/redis/ioredis)
- [ioredis API reference (`RedisOptions`)](https://redis.github.io/ioredis/index.html)
- [node-redis — GitHub README](https://github.com/redis/node-redis)
- [node-redis v4 docs on redis.io](https://redis.io/docs/latest/develop/clients/nodejs/)
- [Redis pipelines and transactions in Node](https://redis.io/docs/latest/develop/clients/nodejs/transpipe/)
- [node-redis v3→v4 migration (camelCase commands)](https://github.com/redis/node-redis/blob/master/docs/v3-to-v4.md)
- [Understanding `@MessagePattern` vs `@EventPattern`](https://medium.com/@bloodturtle/understanding-messagepattern-vs-eventpattern-in-nestjs-microservices-with-kafka-examples-8b33fe11a6d4)
- [Nest Redis integration test controller (reference)](https://github.com/nestjs/nest/blob/master/integration/microservices/src/redis/redis.controller.ts)
- [`@liaoliaots/nestjs-redis`](https://github.com/liaoliaots/nestjs-redis)
- [`@nestjs-modules/ioredis`](https://www.npmjs.com/package/@nestjs-modules/ioredis)
- [Creating a Microservice with `ClientProxy` and `MessagePattern`](https://medium.com/@briankworld/creating-a-microservice-in-nestjs-using-clientproxy-and-messagepattern-c73e938ab18e)
