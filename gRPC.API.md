# gRPC APIs in TypeScript/Node.js — A CPC-Oriented Analysis Reference

This document catalogs the gRPC call-return APIs that a static analyzer must recognize in order to reconstruct **Component-Port-Connector (CPC)** architectures from TypeScript/NestJS microservices, and maps each API to the Axios primitives that the existing analysis already handles. Only **call-return** (unary RPC) style is covered — gRPC streaming is a natural extension but is outside the scope of the current work.

## 1. Libraries We Target

| Library | Role | Notes |
| --- | --- | --- |
| `@grpc/grpc-js` | Canonical pure-JS gRPC client/server | Replaces deprecated native `grpc` package |
| `@grpc/proto-loader` | Dynamic `.proto` parser | Usually paired with `@grpc/grpc-js` |
| `@nestjs/microservices` (+ `Transport.GRPC`) | High-level declarative wrapper | Wraps `@grpc/grpc-js` with decorators |
| `ts-proto` / `grpc_tools_node_protoc_ts` / `proto-loader-gen-types` | TypeScript codegen from `.proto` | Emits nominal TS types for message / service definitions |

## 2. Low-Level `@grpc/grpc-js` API Signatures

### 2.1 Provider (Server) Side

```typescript
import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';

const packageDef = protoLoader.loadSync('hero.proto', { keepCase: true, longs: String, enums: String });
const proto = grpc.loadPackageDefinition(packageDef) as any;

function findOne(
  call: grpc.ServerUnaryCall<FindOneRequest, Hero>,
  callback: grpc.sendUnaryData<Hero>,
) {
  callback(null, { id: call.request.id, name: 'Alice' });
}

const server = new grpc.Server();
server.addService(proto.hero.HeroService.service, { findOne });
server.bindAsync(
  '0.0.0.0:50051',
  grpc.ServerCredentials.createInsecure(),
  () => {},
);
```

| AST construct | Role |
| --- | --- |
| `new grpc.Server(opts?)` | Server instantiation → **Component Type Identity** anchor |
| `server.addService(ServiceDef, impl)` | Registers the **Provider Port** (binds proto service → handler map) |
| `server.bindAsync(address, creds, cb)` | Binds the listen address — first positional string literal holds host+port (or a template over env vars) |
| `grpc.ServerCredentials.createInsecure() / createSsl(...)` | Transport credentials (not CPC-significant for address resolution) |

### 2.2 Requirer (Client) Side

```typescript
const client = new proto.hero.HeroService(
  'localhost:50051',
  grpc.credentials.createInsecure(),
);
client.findOne({ id: 1 }, (err, response) => { /* ... */ });
```

| AST construct | Role |
| --- | --- |
| `new ServiceClient(address, credentials, options?)` | **Requirer Port Creation**. `address` literal or expression holds the **Component Instance Identity** of the remote service |
| `client.<rpcName>(request, cb)` / `util.promisify(...)` | **Message Sending** — unary call-return. Callback receives `(err: ServiceError \| null, resp: T)` |
| `grpc.credentials.createInsecure() / createSsl(...)` | Channel credentials |

## 3. NestJS Declarative gRPC Transport

NestJS hides the `addService` / `ServiceClient` machinery behind decorators and injected proxies. This is the preferred target because it is the shape the existing analysis already works with (the Axios pipeline leans heavily on `ConfigService`-injected URLs).

### 3.1 Provider (Server) Side

```typescript
// main.ts
const app = await NestFactory.createMicroservice<MicroserviceOptions>(AppModule, {
  transport: Transport.GRPC,
  options: {
    url: configService.get<string>('HERO_GRPC_URL'),
    package: 'hero',
    protoPath: join(__dirname, 'proto/hero.proto'),
  },
});

// hero.controller.ts
@Controller()
export class HeroController {
  @GrpcMethod('HeroService', 'FindOne')
  findOne(data: FindOneRequest): Hero {
    return { id: data.id, name: 'Alice' };
  }
}
```

| AST construct | Role |
| --- | --- |
| `NestFactory.createMicroservice(..., { transport: Transport.GRPC, options: { url, package, protoPath } })` | Bootstrap of the gRPC Provider — **Component Type Identity** with its listening address |
| `@GrpcMethod('HeroService', 'FindOne')` | **Provider Port Creation** — the two string literals form the `package.Service/Method` gRPC path |
| `@GrpcStreamMethod(...)`, `@GrpcStreamCall(...)` | Streaming variants (extension — not call-return) |
| Method return value | **Message Sending** (the reply payload) |

### 3.2 Requirer (Client) Side

```typescript
@Module({
  imports: [
    ClientsModule.registerAsync([{
      name: 'HERO_PACKAGE',
      imports: [ConfigModule],
      useFactory: (cfg: ConfigService) => ({
        transport: Transport.GRPC,
        options: {
          url: cfg.get<string>('HERO_GRPC_URL'),
          package: 'hero',
          protoPath: join(__dirname, 'proto/hero.proto'),
        },
      }),
      inject: [ConfigService],
    }]),
  ],
})
export class AppModule {}

@Injectable()
export class AppService implements OnModuleInit {
  private heroService: HeroService;
  constructor(@Inject('HERO_PACKAGE') private client: ClientGrpc) {}

  onModuleInit() {
    this.heroService = this.client.getService<HeroService>('HeroService');
  }

  findOne(id: number) {
    return lastValueFrom(this.heroService.findOne({ id }));
  }
}
```

| AST construct | Role |
| --- | --- |
| `ClientsModule.register([{ name, transport: Transport.GRPC, options: { url, package, protoPath } }])` (and `registerAsync`) | **Requirer Port Creation** + injection token; holds **Component Instance Identity** (`url`) and the `.proto` binding |
| `@Client({ transport, options })` | Legacy property-decorator variant — same semantics |
| `@Inject('HERO_PACKAGE') client: ClientGrpc` | Proxy handle to the remote component |
| `client.getService<T>('HeroService')` | Materialises the strongly-typed stub for a service; the string argument resolves the service name |
| `this.svc.findOne(req)` returning `Observable<T>` | **Message Sending** (call-return) — callers unwrap with `lastValueFrom(...)` / `firstValueFrom(...)` |

## 4. Message Type Generation Pipelines

| Codegen path | Where TS types live | Static-analysis implication |
| --- | --- | --- |
| `@grpc/proto-loader` (dynamic, default for NestJS) | Optional `proto-loader-gen-types` `.d.ts` files | Analyzer may need to parse `.proto` *or* the generated `.d.ts` to recover nominal message types |
| `ts-proto` | Idiomatic TS interfaces emitted alongside `.proto` | Nominal matching is safe — types are named identically on both sides |
| `grpc_tools_node_protoc_ts` | JavaBean-style classes with get/set accessors | Analyzer must unwrap accessor calls to recover the underlying message schema |

Because gRPC is schema-first, **the Message Type is recoverable with nominal certainty** the moment the analyzer has access to the generated TS types — no structural-typing heuristics are needed. This is the decisive contrast with Axios, where message schemas have to be inferred from generics (`axios.post<T>`) or DTO imports.

## 5. Mapping gRPC ↔ Axios (CPC Primitives)

| Axios primitive (current analysis) | `@grpc/grpc-js` counterpart | NestJS gRPC counterpart |
| --- | --- | --- |
| `axios.create({ baseURL })` | `new ServiceClient(address, credentials)` | `ClientsModule.register([{ transport: Transport.GRPC, options: { url, package, protoPath } }])` + `getService<T>('Service')` |
| `axios.post('/users', payload)` | `client.createUser(payload, cb)` | `this.userService.createUser(payload)` → `Observable<User>` |
| URL path `/users/:id` | gRPC wire path `/<package>.<Service>/<Method>` | Same path, assembled from `options.package` + `@GrpcMethod(...)` |
| HTTP method (GET/POST/PUT/DELETE) | *Collapsed* — all unary RPCs are POST-like over HTTP/2; intent lives in the RPC **method name** | Same — method name carries the verb semantics |
| Request body (JSON) | Protobuf-serialized message | Same |
| `AxiosResponse<T>` | Callback `(err, resp: T)` or `util.promisify(...)` result | `Observable<T>` → `lastValueFrom(...)` |
| Headers | `grpc.Metadata` | `Metadata` (via handler param or interceptor) |
| HTTP status codes | `grpc.status.*` delivered as `ServiceError.code` | Propagated as `RpcException` |
| Base URL from `ConfigService.get('X_SERVICE_URL')` | `address` string — typically still from `process.env` or `ConfigService` | `options.url` — exactly the same `ConfigService`-backed pattern the existing analysis already tracks |

## 6. Architectural Element ⇨ Code Construct Summary

This table mirrors the style of the existing REST/Axios mapping in the project's API-analysis document.

| Architectural Element | Code Construct / API Signature | Extraction Mechanism / AST Target |
| --- | --- | --- |
| **Component Type Identity** | `NestFactory.createMicroservice({ transport: Transport.GRPC, ... })`, `new grpc.Server()` | `CallExpression` / `NewExpression` at bootstrap |
| **Component Instance Identity** | `options.url`, first arg to `ServiceClient(addr, ...)`, first arg to `bindAsync(addr, ...)` | String literal or `ConfigService.get('X_GRPC_URL')` — reuse existing URL-resolution data flow |
| **Provider Port Creation** | `@GrpcMethod('Service', 'Method')`, `server.addService(proto.X.service, impl)` | Decorator arg extraction; `CallExpression` on `addService` with service descriptor |
| **Requirer Port Creation** | `ClientsModule.register` / `@Client`, `this.client.getService<T>('Service')`, `new ServiceClient(addr, creds)` | Decorator/module metadata extraction; `NewExpression`; `MethodCallExpr` on `getService` |
| **Port Type** | gRPC path `/<package>.<Service>/<Method>` assembled from the decorator's two string args (+ `options.package`) or from the stub method name | String-literal concatenation of `package` + decorator args; method identifier from call expression on stub |
| **Message Sending** | `client.rpcMethod(req, cb)`, `stub.rpcMethod(req)` (NestJS `Observable`), callback `callback(null, response)` | `CallExpression` on stub object; stream-aware variant for `lastValueFrom` / `firstValueFrom` unwraps |
| **Message Type** | Proto-generated interfaces (`ts-proto` emits nominal TS); `@Payload()` parameter types | Nominal type resolution against generated `.d.ts`; no structural inference needed |

## 7. What Changes in the Existing Analysis Pipeline

The existing pipeline is:

1. **CodeQL query** (`dataflow6.ql`) — taint-tracks `ConfigService.get('*_SERVICE_URL')` sources into Axios sinks and resolves the concatenated URL string.
2. **Python orchestrator** (`tests/query.py`) — parses CSV, resolves `{*_SERVICE_URL}` placeholders against `.env` files, deduplicates.
3. **PlantUML generator** (`converter.py`) — renders the architecture diagram.

To lift this to gRPC, only the **sink definition** and the **port-type extraction** change. The source side (`ConfigService.get(...)`) is identical — gRPC URLs are injected the same way Axios URLs are. Concretely:

- The Axios `isSink` — a `MethodCallExpr` on a receiver named `axios` — becomes a gRPC `isSink` over (a) `NewExpression` with a proto-generated constructor, or (b) `client.getService<T>('Name')` call sites, or (c) NestJS's `ClientsModule.register([{ transport: Transport.GRPC, options: { url } }])` object literal.
- The HTTP-method extraction predicate (`httpMethod(sink)`) is replaced by a gRPC path extractor: service name + RPC method name, optionally prefixed by `package`.
- Everything else — URL resolution (`resolveExprValue`, `resolveTemplateElements`), service identification (`callerService` by file path), env-var substitution in Python, PlantUML rendering — is identical. Those protocol-agnostic parts are precisely what the refactor in the companion `STUDENT_GUIDE.md` extracts into a reusable analysis core.

## 8. Sources

- [gRPC Node Basics Tutorial](https://grpc.io/docs/languages/node/basics/)
- [gRPC Node Quick Start](https://grpc.io/docs/languages/node/quickstart/)
- [`@grpc/proto-loader` on npm](https://www.npmjs.com/package/@grpc/proto-loader)
- [grpc-node `Server` source](https://github.com/grpc/grpc-node/blob/master/packages/grpc-js/src/server.ts)
- [grpc-node `ChannelCredentials` source](https://github.com/grpc/grpc-node/blob/master/packages/grpc-js/src/channel-credentials.ts)
- [gRPC Node API reference — `grpc.Server`](https://grpc.github.io/grpc/node/grpc.Server.html)
- [NestJS gRPC Microservices docs](https://docs.nestjs.com/microservices/grpc)
- [nestjs/nest `client-grpc.ts` source](https://github.com/nestjs/nest/blob/master/packages/microservices/client/client-grpc.ts)
- [Use gRPC with Node.js and TypeScript (dev.to)](https://dev.to/devaddict/use-grpc-with-node-js-and-typescript-3c58)
- [ts-proto — NestJS-compatible codegen](https://github.com/stephenh/ts-proto)
- [gRPC interface style guide — package/service/method URL path](https://eclipse.dev/velocitas/docs/concepts/development_model/val/grpc_style_guide/)
