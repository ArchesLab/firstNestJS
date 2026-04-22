# Statically Extracting Microservice Architectures: A Student's Guide

Hi! This guide walks you through how this project reconstructs **Component-Port-Connector (CPC)** architectures from TypeScript/NestJS microservices — and how I extended it from Axios (HTTP) to also cover **gRPC** and **Redis (call-return)**. It's written for a sophomore CS student who has seen TypeScript, understands what an AST is, and is willing to think carefully.

This file is the companion to two deep API references:
- [`gRPC.API.md`](./gRPC.API.md) — the gRPC mapping.
- [`Redis.API.md`](./Redis.API.md) — the Redis call-return mapping.

> Content is added to this guide in three phases: (1) the research and API mappings, (2) the description of a semantics-preserving refactor that extracts a shared analysis core, and (3) a future-work section grounded in a literature survey. Later sections are added in later commits.

## 1. What Problem Are We Solving?

A **microservice architecture** is a mesh of independently deployable services that talk to each other over the network. Over time, nobody keeps the system-wide picture in sync with reality. This project reconstructs that picture *from the source code*, before the system is even deployed. The output is a diagram you can read, diff against prior versions, and use to catch architectural drift.

The shape we reconstruct is the classical **Component-Port-Connector** model:
- **Components** are services (one per deployable unit — in this repo: `auth`, `clubs`, `events`, `gateway`, `notifications`, `users`).
- **Ports** are named, directional interfaces a component exposes or uses. A **provider port** accepts incoming messages; a **requirer port** issues outgoing messages.
- **Connectors** are the edges between a requirer port on one component and a provider port on another.

In code, **components** are whole services, **ports** are things like a route decorator (`@Get('/users')`) or an Axios call site (`axios.post(url)`), and **connectors** are the synthesized edges the analyzer produces when a requirer's URL resolves to a provider's route.

## 2. The Starting Point: How the Axios Analysis Works

The existing pipeline has three stages:

```
CodeQL query  →  CSV rows  →  Python orchestrator  →  final_result.txt  →  PlantUML renderer  →  diagram.puml
(dataflow6.ql)                    (tests/query.py)                           (converter.py)
```

### Stage 1 — CodeQL ([`dataflow6.ql`](my-research-project/dataflow6.ql))
A **taint-tracking** query. The *source* is any call to `.get()` on a receiver whose name contains `config` (NestJS's `ConfigService.get('X_SERVICE_URL')` pattern). The *sink* is the first argument to a call whose receiver is the identifier `axios`. Between them, the query tracks flow, including across property writes/reads on `this`.

When a flow is found, the query calls `resolveExprValue(expr)` — a ~100-line recursive predicate that rebuilds the **logical string** of the URL argument. It handles:
- string literals, number literals
- `AddExpr` concatenation (including mixed string/number)
- template literals (recursively walking each interpolated element)
- `ConfigService.get('X')` calls, which it emits as the placeholder string `"{X}"`
- `VarAccess` resolved via `DataFlow::localFlowStep*`
- property access on `this` when there's a matching `this.X = Y` assignment
- `AwaitExpr`, `LogicalBinaryExpr` (`||`), inter-procedural call-and-return
- numeric arithmetic (via a separate `valueOf` predicate for integer folding)

The query also computes `callerService(sink)` (hard-coded file-path matching for the six sample services) and `httpMethod(sink)` (the method name of the Axios call). Output columns: `source | callerService | configKey | sink | resolvedEndpoint | httpMethod`.

### Stage 2 — Python ([`tests/query.py`](my-research-project/tests/query.py))
Reads the CSV, loads every `.env` file, finds every `{X_SERVICE_URL}` placeholder in `resolvedEndpoint` and substitutes the concrete URL, then deduplicates rows by `(callerService, envVarTuple, httpMethod)`. Emits a pipe-delimited `final_result.txt`.

### Stage 3 — PlantUML ([`converter.py`](my-research-project/converter.py))
Parses `final_result.txt`, infers the **target** service from the first URL-path segment (so `/users/...` → `users`), and emits a PlantUML diagram with `portin` ports and labeled edges.

Example final output (from the current repo):
```
notifications --> users_port : "patch /users/unsubscribe/{userId}"
auth --> clubs_port : "get /clubs/roles/{clubId}/{userId}"
gateway --> users_port : "get /users"
```

## 3. Extending the Analysis to gRPC and Redis

### 3.1 Why the Existing Pipeline Generalizes

The CPC model is protocol-agnostic. The reason the Axios pipeline can be extended rather than rewritten is that **only two things change per protocol**:

1. **The sink shape** (which call expressions constitute a requirer port).
2. **The port-type extraction** (how to turn the sink's arguments into a port-type string).

Everything else is shared:
- The source is still `ConfigService.get('...')` — gRPC URLs and Redis hosts are wired through the same `@nestjs/config` machinery.
- Expression resolution (template literals, property writes on `this`, inter-procedural returns) is language-level, not protocol-specific.
- File-path-to-service mapping, `.env` resolution, dedup, and PlantUML rendering are all downstream of the protocol-specific bits.

### 3.2 The gRPC Mapping (summary — full detail in [gRPC.API.md](./gRPC.API.md))

| Axios | gRPC (`@grpc/grpc-js`) | gRPC (NestJS) |
| --- | --- | --- |
| `axios.create({baseURL})` | `new ServiceClient(addr, creds)` | `ClientsModule.register([{ transport: Transport.GRPC, options: { url, package, protoPath } }])` |
| `axios.post('/path', payload)` | `client.rpc(req, cb)` | `this.svc.rpc(req)` → `Observable<T>` |
| URL path | `/<package>.<Service>/<Method>` (from proto) | Same, from `options.package` + `@GrpcMethod('Service', 'Method')` |
| HTTP verb | Collapsed (all unary RPCs are POST-like) | Same |
| Message Type | Protobuf message, nominally typed via `ts-proto` / `proto-loader-gen-types` | Same |

**What the analyzer gains:** because gRPC is schema-first, message types are **nominally** typed. That means a message-type match between requirer and provider is exact — no structural-typing false positives.

**What the analyzer loses:** the `.proto` file is *outside* the TS source. CodeQL's JavaScript extractor doesn't parse `.proto`. Two workable options: (a) parse the `.d.ts` files emitted by `proto-loader-gen-types` or `ts-proto`; (b) extract the port-type just from the decorator arguments (`@GrpcMethod('Service', 'Method')`).

### 3.3 The Redis Call-Return Mapping (summary — full detail in [Redis.API.md](./Redis.API.md))

Two variants, both call-return:

**Variant A — Direct Redis commands (`ioredis`, `node-redis`).** A cache/data-store interaction. The requirer port is `@Inject('REDIS_CLIENT') redis: Redis`; each `redis.get(key)`, `redis.set(key, value)`, `redis.hset(...)` etc. is a sink. The port type is `(command, key)`; the message type is the value.

**Variant B — NestJS Redis microservice transport with `@MessagePattern`.** Same programming model as Axios with URL + JSON — the client does `client.send({cmd: 'sum'}, payload)` and awaits the response; the server handles with `@MessagePattern({cmd: 'sum'})`. Pub/sub is used *under the hood* but the API surface is synchronous.

> **Critical disambiguation:** `@MessagePattern` is request-response (in scope). `@EventPattern` is fire-and-forget (out of scope — per the assignment). The analyzer must reject `@EventPattern` handlers.

| Axios | Direct Redis | NestJS Redis RPC |
| --- | --- | --- |
| `axios.create({baseURL})` | `new Redis({host, port})` / `createClient({url})` | `ClientsModule.register([{ transport: Transport.REDIS, options: { host, port } }])` |
| `axios.post('/path', body)` | `redis.set('user:42', JSON.stringify(user))` | `client.send({cmd:'route'}, payload)` |
| URL path | Redis **key** (`user:42`) | **Pattern** (`'sum'` or `{cmd:'sum'}`) |
| HTTP verb | Redis **command** (`GET`, `SET`, `HSET`, ...) | Not applicable |

## 4. Static Analysis & CodeQL: Edge Cases to Reason About

Writing a query that works on a toy sample is easy. Writing one that survives a real codebase is hard. Here are the sharpest edges in this pipeline — some of which the current Axios query already hits.

### 4.1 Sink shape in Axios (`dataflow6.ql`)
- Only `axios.get/post/put/delete/patch` with literal receiver `axios` is matched.
- **Missed in this repo:** `users/src/clubs-client.service.ts:27` uses `this.httpService.get<Club>(...)` from `@nestjs/axios` — the receiver is `httpService`, not `axios`. That sample has a genuine Axios call silently dropped by the current analyzer.
- Also missed: `axios.head`, `axios.options`, `axios.request(cfg)`, `axios(cfg)` as a function, `axios.create(...).get(...)`, destructured methods, `fetch`, `got`, `undici`.

### 4.2 Source predicate is loose
`isSource` in `dataflow6.ql` matches *any* `.get()` whose receiver's name contains `config`. It also injects every `StringLiteral` as a source (lines 32–34). That means the taint graph starts from a very broad set of nodes. A future tightening would filter `mc.getAnArgument().(StringLiteral).getValue().matches("%_URL%")` (the way `dataflow5.ql` does).

### 4.3 Redis vs Config collision
`redis.get(key)` and `configService.get('KEY')` have the **same method name**. A naive "match any `.get()`" source or sink will confuse them. Disambiguation must be **by receiver type**, not by method name alone:
- For sources: require the receiver to be a `ConfigService` (injected via DI or annotated).
- For sinks: require the receiver to be a Redis client (`new Redis()`, `createClient()`, or bound via `@Inject('REDIS_CLIENT')`).

### 4.4 Expression resolution, specifically
`resolveExprValue` is impressive but doesn't handle:
- `ConditionalExpression` (`cond ? 'a' : 'b'`)
- `TaggedTemplateExpression` (`gql\`...\``)
- `TypeAssertion` / `as` cast / `NonNullAssertion` (`x!`) / parenthesized expressions
- Optional chaining (`configService?.get('X')` is an `OptionalCallExpr`, not a `MethodCallExpr`)
- String methods (`url.toLowerCase()`, `url.replace()`, `url.trim()`)
- `Array.prototype.join(['/', a, b])`
- Object-held values (`this.cfg = {url: X}; this.cfg.url`)

Each falls through to the "Refined Fallback" arm, which wraps the expression's raw text in `{...}` — producing CSV rows that look resolved but aren't actionable downstream.

### 4.5 `this.X = Y → this.X` property tracking is unscoped
The `isAdditionalFlowStep` predicate matches any `this.X = Y` write to any `this.X` read with the same property name — **without** checking they're in the same class. Two classes that both use `this.url` can cross-pollinate the taint graph. In a small monorepo this is rare; at scale it's a false-positive generator.

### 4.6 `LogicalBinaryExpr` yields non-determinism
`resolveExprValue(a || b)` returns *both* values as disjuncts. That's correct for correctness (either could hold at runtime) but produces N rows per sink — which the Python dedup then collapses by `(callerService, envVars, httpMethod)` tuple, **losing** the distinction between them.

### 4.7 Wrong argument index for `axios.request(cfg)`
`sink = axiosCall.getArgument(0)` picks arg 0 as the URL. That's right for `axios.get(url)` but wrong for `axios.request({url, method})`, where arg 0 is the config object and the URL is `cfg.url`. If this were ever added, the resolver would try to stringify the object literal.

### 4.8 Service identification by file path
`callerService` hardcodes six folder names. Any new service, any hyphenated name (`user-service/`), any nested monorepo layout requires editing the query. The fallback `unknown-service` at least doesn't drop the row — that's good — but a real tool would read the service list from `package.json` names or a config file.

### 4.9 Python env-var resolution
`tests/query.py` hardcodes Windows absolute paths (`C:\Users\mary\...`). On any other machine it silently loads an empty env dict and produces no resolved rows. It also filters on `[A-Z][A-Z0-9_]*_URL` only — gRPC hosts (`HERO_GRPC_HOST`), Redis hosts (`REDIS_HOST`), and anything not ending in `_URL` are dropped.

### 4.10 PlantUML target inference
`converter.py` infers the target service from `path_parts[0]` of the URL path. That works because every sample service uses `@Controller('<serviceName>')`. It breaks for:
- Services with empty `@Controller()` at root (the `gateway` in this repo).
- Redis keys (separator is `:`, not `/`).
- gRPC paths (the first segment is `<package>.<Service>`, not a service name).

### 4.11 Cross-repo reality
The pipeline runs on *one* CodeQL database at a time. A real microservice mesh lives in multiple repos. The architecture graph only fully assembles when per-repo CSVs are merged and requirer ports are matched against provider ports across separate extractor runs. Component-identity reconciliation (*is `USERS_SERVICE_URL` in caller A the same `users` service that caller A' calls?*) then becomes a merge/synthesis step, not a CodeQL step.

### 4.12 gRPC-specific
- `.proto` is not TS — CodeQL's JS extractor doesn't see it. Parse the emitted `.d.ts` or decorator args.
- `this.svc.findOne(req)` returns `Observable<T>` — if analysis requires `lastValueFrom`/`firstValueFrom` to recognize "call-return", pure observable calls are missed.
- `client.getService<T>('Name')` — the string argument is authoritative; the generic is advisory.

### 4.13 Redis-specific
- Broker address ≠ target service address. Many `@MessagePattern` handlers can share one broker.
- `@MessagePattern('name')` (string) vs `@MessagePattern({cmd:'name'})` (object) — two shapes.
- Filter out `@EventPattern` (pub-sub).

## 5. How These Edges Shape the Design

The edge-case list above has a clear takeaway: **the protocol-agnostic parts of the pipeline (expression resolution, service identification, env resolution, rendering) carry most of the complexity**. The protocol-specific parts (what a sink looks like, what the port type is) are relatively simple per-protocol wrappers.

That's exactly why a semantics-preserving refactor makes sense before adding gRPC and Redis. Without it, each new protocol would duplicate `resolveExprValue`, `callerService`, and the env-merging logic — tripling the surface area where bugs can drift between implementations. The refactor (added in the next commit) pulls the shared core into dedicated modules so the gRPC and Redis extensions become small, focused additions rather than parallel rewrites.

## 6. The Refactor — Extracting a Shared Analysis Core

After writing the API mappings, I performed a **semantics-preserving** refactor that pulls the protocol-agnostic parts of the pipeline into dedicated modules. "Semantics-preserving" has a precise meaning here: running the refactored pipeline on the existing Axios sample must produce the same `final_result.txt` and the same `diagram.puml` as before — byte-for-byte. It does, and I verified it on the checked-in `codeql_results.csv`.

### 6.1 What moved where

**CodeQL** (new `my-research-project/lib/` folder):

| New file | Contents |
| --- | --- |
| `lib/ExprResolution.qll` | `valueOf`, `resolveExprValue`, `resolveTemplateElements`, `resolveUrlAtSink` — the ~100-line recursive string resolver that rebuilds URLs/pattern strings from ASTs |
| `lib/ServiceIdentification.qll` | `callerService` — the file-path-based service naming predicate |
| `lib/ConfigSource.qll` | `isConfigServiceGetCall` (the source predicate) and `thisPropertyFlowStep` (the `this.X = Y → this.X` transfer step) |

`dataflow6.ql` shrinks from ~310 lines to ~55 lines. What remains is exactly the protocol-specific parts for Axios: the `isSink` predicate (receiver named `axios`, sink is argument 0) and `httpMethod(sink)` (the verb extractor). The CodeQL `DataFlow::ConfigSig` implementation now reads as:

```ql
module ConfigToAxiosConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) { isConfigServiceGetCall(source) }
  predicate isSink(DataFlow::Node sink) {
    exists(MethodCallExpr axiosCall |
      axiosCall.getReceiver().(Identifier).getName() = "axios" and
      sink = DataFlow::valueNode(axiosCall.getArgument(0))
    )
  }
  predicate isAdditionalFlowStep(DataFlow::Node pred, DataFlow::Node succ) {
    thisPropertyFlowStep(pred, succ)
  }
}
```

Adding gRPC will mean writing a sibling `.ql` query that keeps the same three lib imports and swaps `isSink` / `httpMethod` for gRPC-shaped variants (`client.getService<T>('X')` sinks, port-type built from `@GrpcMethod` args). Redis will do the analogous thing for `@MessagePattern` + `client.send(...)`.

**Python** (new `my-research-project/pipeline/` package):

| New file | Contents |
| --- | --- |
| `pipeline/models.py` | `ConnectorEdge` dataclass — the unified CPC-edge representation |
| `pipeline/env_resolver.py` | `.env` file merging, placeholder substitution, `*_SERVICE_URL` → service-name inference |
| `pipeline/csv_parser.py` | CodeQL CSV → `ConnectorEdge` iterator with resolution and skip rules preserved |
| `pipeline/formatter.py` | `ConnectorEdge` → pipe-delimited text with the exact column widths used before |
| `pipeline/text_parser.py` | Pipe-delimited text → `ConnectorEdge`, with helpers to split the URL into base + path and infer target service |
| `pipeline/plantuml.py` | Edge list → PlantUML string, with the same hardcoded components list and set-based dedup |

`tests/query.py` and `converter.py` become thin entry-point wrappers that call into the pipeline. Their hardcoded paths and component lists are preserved (the refactor does not fix pre-existing issues — that would change behaviour).

### 6.2 Why this specific factoring

The edge-case analysis in Section 4 makes the carve-out obvious: the parts of the pipeline that carry most of the complexity (expression resolution, env merging, service inference, dedup rules, output formatting) are the same regardless of whether the sink is an `axios.post` or a `redis.get` or a `client.send`. Leaving them inlined in `dataflow6.ql` / `query.py` / `converter.py` would force every new protocol to copy-paste or re-implement them — a classic drift hazard.

Three specific design choices follow from the edge analysis:

1. **The source predicate lives in a library.** Axios, gRPC, and Redis all consume `ConfigService.get('X_SERVICE_URL')` (or `X_GRPC_URL`, `REDIS_HOST`). The URL-resolution machinery doesn't care which protocol consumes the string — only the sink cares. So the source is genuinely protocol-agnostic.
2. **The `this.X = Y → this.X` transfer step lives in a library.** Every NestJS service stores injected config in a `readonly` property in the constructor. All three protocols need that transfer step.
3. **`httpMethod(sink)` stays *inline* in `dataflow6.ql`.** The port-type verb is intrinsically Axios-specific — a gRPC query will replace this predicate with one that returns `<package>.<Service>/<Method>`, and a Redis query with one that returns the command verb or routing pattern. Hoisting `httpMethod` to a library would pull a protocol-specific concept into the shared core, which is a smell. Leaving it beside its `isSink` keeps each query self-contained for its protocol.

### 6.3 Correctness testing

I verified the refactor against the existing `codeql_results.csv` by running both the pre-refactor and post-refactor Python pipelines and diffing their outputs:

- **Stage 1** (`query.py` → `final_result.txt`): byte-identical.
- **Stage 2** (`converter.py` → `diagram.puml`): byte-identical (and, because Python's set-based dedup in `converter.py` already produced hash-order-dependent output, the refactor preserves the same ordering behaviour as before).

The CodeQL side can only be verified by running `codeql database analyze` on a NestJS database, which requires the CodeQL CLI. Manually diffing `dataflow6.ql` against its pre-refactor form shows that the only semantic-bearing changes are three `import` lines; every extracted predicate (`valueOf`, `resolveExprValue`, `resolveTemplateElements`, `resolveUrlAtSink`, `callerService`, `isConfigServiceGetCall`, `thisPropertyFlowStep`) is verbatim.

### 6.4 What the refactor does *not* do

On purpose:
- It does not generalize `callerService` (still hard-coded for the six sample services). Changing that would change output for new codebases — not semantics-preserving.
- It does not tighten the overly-broad source predicate (see §4.2 / §4.3). Tightening it to require `%_URL%` in the config key would drop StringLiteral sources and alter the set of reported flows.
- It does not fix the Windows hardcoded paths in `tests/query.py`. Parameterising them would be trivial but again would be a behaviour change — the refactor leaves the constants visible as module-level `DEFAULT_*` so a follow-up can add a CLI flag without touching the core.
- It does not add gRPC or Redis support. The refactor creates the *platform* for those extensions; the extensions themselves are the next concrete work item.

## 7. Future Work — Grounded in the Literature

The refactor gives us a clean platform, but the edges in §4 — dynamic URL construction, structural typing, cross-repository reconciliation, loose source predicates, and brittle service identification — remain real limits on the analysis. This section connects each of those edges to published work we can build on, drawing from a targeted literature survey over OpenAlex, arXiv, and the major SE venues.

### 7.1 Microservice architecture recovery — the direct baseline

The closest methodological ancestor to our CodeQL-based analysis is the Baylor/Cerny group's body of work on statically reconstructing Spring Boot service meshes.

1. **Bushong, Das, Al Maruf, and Cerny (2021).** *Using Static Analysis to Address Microservice Architecture Reconstruction.* ASE 2021. DOI: [10.1109/ASE51524.2021.9678749](https://doi.org/10.1109/ASE51524.2021.9678749).
   This paper statically extracts HTTP-level communication between Spring Boot Java microservices and renders a communication diagram + context map. It is essentially our pipeline, one protocol over, one language over. Its *explicit* limits — Java only, REST only, reliant on Spring annotations — are exactly what the present work extends. Their HTTP endpoint-matching strategy is the direct analogue of our connector-synthesis step, and their reliance on annotations is what we rely on too (`@GrpcMethod`, `@MessagePattern`, `@Controller`).
2. **Bushong, Das, and Cerny (2022).** *Reconstructing the Holistic Architecture of Microservice Systems using Static Analysis.* CLOSER 2022. DOI: [10.5220/0011032100003200](https://doi.org/10.5220/0011032100003200).
   Extends the prior work to multi-view recovery (service graph + bounded context + data model). The multi-view framing is a natural extension for our future work: once we recover gRPC/Redis edges, we can layer a data-model view (which services share a Redis datastore, which proto messages cross which edges).
3. **Schiewe, Curtis, Bushong, and Cerny (2022).** *Advancing Static Code Analysis With Language-Agnostic Component Identification.* IEEE Access. DOI: [10.1109/ACCESS.2022.3160485](https://doi.org/10.1109/ACCESS.2022.3160485).
   Proposes a language-agnostic intermediate representation for microservice SAR, prototyped on Java Spring and .NET. Our TypeScript extractor is the *third* ecosystem this IR would need to target, and the paper's abstractions directly motivate why the refactor split `ConnectorEdge` / `ExprResolution` out of the Axios-specific code.
4. **Cerny, Abdelfattah, Bushong, Al Maruf, and Taibi (2022).** *Microservice Architecture Reconstruction and Visualization Techniques: A Review.* SOSE 2022. DOI: [10.1109/SOSE55356.2022.00011](https://doi.org/10.1109/SOSE55356.2022.00011).
   A systematic review cataloguing static, dynamic, and hybrid SAR approaches. Its explicit gap list — polyglot microservices, multi-protocol connectors, weak tool support beyond Java — is the single most useful positioning for this work, and confirms that extending to TypeScript + gRPC + Redis fills recognised gaps.
5. **Schneider, Bakhtin, Li, Soldani, Brogi, Cerny, Scandariato, and Taibi (2025).** *Comparison of Static Analysis Architecture Recovery Tools for Microservice Applications.* Empirical Software Engineering. DOI: [10.1007/s10664-025-10686-2](https://doi.org/10.1007/s10664-025-10686-2).
   A head-to-head comparison of static microservice SAR tools on a shared benchmark, reporting individual F1 up to 0.86 and an ensemble F1 of 0.91. Tells us two things: (a) there's a shared benchmark we should submit against; (b) no single tool yet handles all languages and protocols well — direct empirical support for building the gRPC + Redis extensions.
6. **Wang, Hu, Kong, Ouyang, Li, Xu, and Shao (2023).** *Microservice architecture recovery based on intra-service and inter-service features.* Journal of Systems and Software. DOI: [10.1016/j.jss.2023.111754](https://doi.org/10.1016/j.jss.2023.111754).
   Combines intra-service and inter-service features to cluster services and recover the architecture. The feature-engineering insight (weighted call-site signatures for inter-service edges) bears directly on how our connector-synthesis step should weight Axios vs. gRPC vs. Redis evidence when the same requirer calls into multiple transports.

### 7.2 Component-port-connector recovery from other ecosystems — ROS as a methodological template

The single closest methodological parallel to this work is the CMU group's ROS-focused line. Robots and microservice meshes are astonishingly similar from an SAR perspective: components communicate over API calls whose targets are strings that are almost never literals, configuration is late-bound, and the "architecture" only exists implicitly in the composition of scattered source and config files.

7. **Timperley, Dürschmid, Schmerl, Garlan, and Le Goues (2022).** *ROSDiscover: Statically Detecting Run-Time Architecture Misconfigurations in Robotics Systems.* ICSA 2022. DOI: [10.1109/ICSA53651.2022.00019](https://doi.org/10.1109/ICSA53651.2022.00019).
   The direct methodological template. Nodes are components, topics/services are ports, and dynamic name resolution mirrors our `process.env`-based URL reconstruction. Its three-stage pipeline (Component Model Recovery → System Architecture Composition → Bug Detection via Rule Checking) maps almost one-to-one onto our `dataflow6.ql` → `query.py` → `converter.py` pipeline. The paper's symbolic-execution recipe for resolving topic names — where variables that depend on parameter reads are tracked through their reaching definitions and the results of parameter lookups are represented symbolically — is the concrete template we need for resolving Axios base URLs, gRPC method strings, and Redis keys. Especially relevant to §4.4 (expression resolution edges) and §4.11 (cross-repo reality): ROSDiscover explicitly mentions that the approach is "generalizable" to microservice frameworks (e.g. Spring, Kafka), which is exactly the bridge our TypeScript extractor begins to build.
8. **Dürschmid, Timperley, Garlan, and Le Goues (2024).** *ROSInfer: Statically Inferring Behavioral Component Models for ROS-based Robotics Systems.* ICSE 2024. DOI: [10.1145/3597503.3639206](https://doi.org/10.1145/3597503.3639206).
   Extends ROSDiscover from structural CPC reconstruction to behavioural component models — state machines over publish/subscribe interactions — via cross-repository static analysis of heterogeneous ROS codebases. For our work, once we reliably recover the CPC graph across Axios/gRPC/Redis, ROSInfer's approach is the natural next rung: move from "service A calls service B" to "service A has a state machine in which method X is called only after method Y". That is how architecture recovery stops being a picture and becomes an enforceable contract.
9. **Timperley et al. (2024).** *ROBUST: 221 Bugs in the Robot Operating System.* Empirical Software Engineering. DOI: [10.1007/s10664-024-10440-0](https://doi.org/10.1007/s10664-024-10440-0).
   An empirical bug study showing a substantial fraction of ROS defects are architectural/configuration mismatches — exactly the bug class our extended extractor could catch in microservices. The taxonomy (missing publisher, mismatched topic name, type incompatibility) maps directly onto what the analyzer must detect in a mesh (requirer without provider, URL typo, DTO mismatch). A practical future-work item is to produce an analogous catalogue for real microservice repos and evaluate the extended extractor against it.

### 7.3 Dynamic name resolution — the symbolic-execution toolbox

Section 4.4 lists a long tail of expression shapes the current `resolveExprValue` cannot fold: ternaries, optional chaining, string methods, tagged templates, array joins, union values. Scaling out of these toward full-string reasoning requires tooling already well established in the security community.

10. **Saxena, Akhawe, Hanna, Mao, McCamant, and Song (2010).** *A Symbolic Execution Framework for JavaScript (Kudzu).* IEEE S&P 2010. DOI: [10.1109/SP.2010.38](https://doi.org/10.1109/SP.2010.38).
    The foundational work for symbolic execution of JavaScript, combining a JS symbolic executor with a string-constraint solver. Motivated by client-side XSS discovery, but the engine is exactly what we need for Component-Instance-Identity resolution: recovering path parameters and URL fragments concatenated from environment variables and route builders. Replacing our hand-rolled `resolveExprValue` with a Kudzu-style engine would close most of the §4.4 gaps at once.
11. **Ganesh, Kieżun, Artzi, Guo, Hooimeijer, and Ernst (2011).** *HAMPI: A String Solver for Testing, Analysis and Vulnerability Detection.* Lecture Notes in Computer Science. DOI: [10.1007/978-3-642-22110-1_1](https://doi.org/10.1007/978-3-642-22110-1_1).
    HAMPI is the canonical string-constraint solver underpinning Kudzu and many later analyses. It solves constraints over fixed-size string variables with regular-language and context-free constraints. For our extractor, HAMPI-style solving is the concrete technique needed to turn a symbolic URL like `${baseUrl}/users/${userId}/orders` into a finite set of concrete endpoint candidates that can be matched against provider ports synthesised from `@Controller` / `@GrpcMethod` / `@MessagePattern` decorators.

### 7.4 Evolution, benchmarking, and framing

12. **Alshuqayran, Ali, and Evans (2018).** *Towards Micro Service Architecture Recovery: An Empirical Study.* ICSA 2018. DOI: [10.1109/ICSA.2018.00014](https://doi.org/10.1109/ICSA.2018.00014).
    One of the earliest empirical investigations of microservice SAR, mining eight OSS systems to identify patterns of inter-service dependency, deployment, and communication. It establishes the problem space our work operates in and is still the canonical "why" citation for every new extractor.
13. **Cerny, Abdelfattah, Yero, and Taibi (2024).** *From Static Code Analysis to Visual Models of Microservice Architecture.* Cluster Computing. DOI: [10.1007/s10586-024-04394-7](https://doi.org/10.1007/s10586-024-04394-7).
    Integrates multiple static analyses into unified visual models for Spring-based stacks. Its extractors → IR → views structure is a larger-scale version of the `pipeline/` package introduced by the refactor, and the paper explicitly lists multi-language support as future work — which our TypeScript extension contributes to.
14. **Abdelfattah, Cerny, Yero Salazar, Li, Taibi, and Song (2024).** *Assessing Evolution of Microservices Using Static Analysis.* Applied Sciences. DOI: [10.3390/app142210725](https://doi.org/10.3390/app142210725).
    Proposes seven service-view and data-view metrics computed purely from static analysis to track microservice evolution across versions. Because our extractor produces time-series inputs naturally (just run it on historical commits), this is an immediate downstream use case the refactor enables — the edges are protocol-independent, so metrics defined over them are too.

### 7.5 What this implies as next work

Putting §4 (edges) and §7.1–§7.4 (literature) together produces a concrete roadmap:

- **Sharpen the source predicate** (§4.2) by typing `ConfigService` through its DI binding, following the ROSDiscover pattern of combining API identification with variable resolution.
- **Disambiguate `redis.get` from `configService.get`** (§4.3) by receiver-type matching, not name matching — straightforward once the core supports typed sinks.
- **Replace `resolveExprValue` with a string-constraint-backed resolver** (§4.4, §4.7) building on Kudzu + HAMPI — this is the biggest quality lever the roadmap offers, and it directly addresses the path-sensitivity gap called out in ROSDiscover's own discussion section.
- **Cross-repository synthesis** (§4.11) by running the extractor per repository and adding an explicit merge step that reconciles `*_SERVICE_URL` consumers with their corresponding providers — mirrors the "System Architecture Composition" stage in ROSDiscover and the unified visual model in Cerny 2024.
- **Benchmarking** against Schneider et al. 2025's shared SAR benchmark once the gRPC and Redis extensions are in place, giving empirical grounding for the contribution.
- **Evolution tracking** (Abdelfattah et al. 2024) as an immediate downstream application once the analysis is stable.

The refactor is the enabling step. Everything above either adds a new lib/*.qll predicate, a new pipeline/ module, or a per-protocol sibling of `dataflow6.ql` — shapes the refactor was explicitly designed to absorb.
