# Extending ROSDiscover-style Architecture Recovery to TypeScript Microservices

A walkthrough of how we turned the ideas in *ROSDiscover: Statically Detecting Run-Time Architecture Misconfigurations in Robotics Systems* (Timperley et al., ICSA 2022) into a CodeQL + Python toolkit that recovers the architecture of a NestJS monorepo that talks over **REST (Axios)**, **gRPC**, and **Redis** — call-return only, no pub-sub.

> Audience: a sophomore who knows some TypeScript, has heard the words "static analysis", and wants to see how a research paper becomes working code.

---

## 1. The problem, in one paragraph

Modern backends are glued together out of many small services. Each service knows where to find its collaborators through configuration — an environment variable like `USERS_SERVICE_URL`, a gRPC channel, a Redis host. The wiring is *late-bound*: nothing in the source code says "service A is connected to service B"; it just happens at runtime when someone starts the processes with the right config. That makes silent misconfigurations frighteningly easy: rename a URL in one place but forget to update the caller, and calls vanish into a 404 at 3 a.m.

The ROSDiscover paper shows how to **recover** the run-time architecture statically and then **check rules** on it. The authors did it for ROS (robots, C++); we want the same idea for NestJS microservices in TypeScript.

---

## 2. What ROSDiscover actually does (a sophomore's cheat sheet)

The paper's pipeline is three stages:

1. **Component Model Recovery** — For each node (a process), read the source code and produce a *symbolic summary*: what topics it publishes, what services it calls, what parameters it reads. Done by walking the AST and resolving interesting API calls.
2. **System Architecture Composition** — Parse the ROS launch files (XML that spells out which nodes to start and how to rename their topics at runtime) and stitch the per-node summaries into a single graph of components joined by connectors.
3. **Bug Detection via Rule Checking** — Turn the graph into first-order-logic predicates and ask an architecture-style checker (Acme) whether any well-formedness rule is violated.

Three things mattered for the approach to work:

- **Well-defined API:** There's a *small* set of ROS functions that carry architectural meaning (`advertise`, `subscribe`, `call`, …). You only need to understand those, not the entire codebase.
- **Quasi-static architectures:** The wiring rarely changes after startup, so static analysis is a good fit.
- **Small core library:** Much of the "weird" behaviour lives in a handful of shared ROS packages that can be modelled by hand once.

Our microservices world has the same three properties. Swap "ROS API" for "Axios / gRPC / Redis API", swap "launch files" for `.env` files, and the argument still holds.

---

## 3. Where we started

Before this change, the repo already had a TypeScript version of stage 1 for Axios only:

- `my-research-project/dataflow6.ql` — a ~300-line CodeQL query that tracks data from `configService.get("FOO")` to `axios.xxx(url, …)` and prints a big table.
- `my-research-project/converter.py` — a Python script that parses that table and renders `diagram.puml`.
- Six sample NestJS services (`auth/`, `users/`, `clubs/`, `events/`, `gateway/`, `notifications/`) all talking to each other through Axios.

Everything worked, but the design had two problems:

1. **Axios-only.** There was no gRPC support, no Redis support. Adding a second protocol by copy-pasting the query would have doubled its size every time.
2. **Hard to reason about.** URL resolution, taint tracking, caller-name identification, and HTTP-method extraction all lived in one file.

So we refactored first, then extended.

---

## 4. The refactor: split the monolith into layers

We reorganised `my-research-project/` into three layers that mirror the three stages of the paper:

```
my-research-project/
├── lib/                         <-- shared helpers (“how do I resolve a string?”)
│   ├── ExprResolution.qll       <-- symbolic string resolution
│   ├── ServiceIdentification.qll<-- which workspace folder owns a file
│   └── Connector.qll            <-- abstract base class for every connector
│
├── connectors/                  <-- one file per protocol
│   ├── AxiosConnector.qll       <-- REST via axios.*
│   ├── GrpcConnector.qll        <-- gRPC unary calls
│   └── RedisConnector.qll       <-- Redis call-return commands
│
├── all_connectors.ql            <-- unified query that asks each connector
│                                     module for its records
│
└── pipeline/                    <-- Python, stage 2 + 3
    ├── models.py                <-- the ConnectorRecord dataclass
    ├── parser.py                <-- CodeQL output -> records
    ├── normalizers.py           <-- per-protocol cleanup
    ├── plantuml_renderer.py     <-- records -> .puml
    └── converter.py             <-- orchestrator / entry point
```

The guiding principle is **"add a protocol without editing anything that already works"**. Concretely that means:

- Every connector is a subclass of one abstract class, `Connector`, that promises six predicates (`getProtocol`, `getOperation`, `getCallerService`, `getTargetService`, `getEndpoint`, `getConfigKey`).
- The unified query simply asks `from Connector c select …`. It never mentions Axios, gRPC, or Redis. Adding a fourth protocol is: write a `.qll`, add one `import` line.
- On the Python side, every protocol-specific behaviour is a function in `normalizers.py` registered in a dictionary. Again, one line to add a protocol.

---

## 5. How each protocol is detected

### 5.1 REST via Axios (legacy behaviour, preserved)

The detection pattern is "a method call where the receiver is the `axios` identifier and the method is an HTTP verb". The tricky part is finding the *URL* argument's concrete value, because NestJS idiomatically does:

```ts
constructor(private readonly configService: ConfigService) {
  this.usersBase = configService.get<string>('USERS_SERVICE_URL');
}
async createUser(payload) {
  return axios.post(`${this.usersBase}/users`, payload);
}
```

There's a property write in the constructor, a property read at the call site, a template literal, and a config lookup all in the chain. CodeQL's **taint tracking** handles the flow, and a recursive `resolveExprValue` predicate (see `lib/ExprResolution.qll`) symbolically reduces the template to `"{USERS_SERVICE_URL}/users"`. That placeholder `{…}` is the equivalent of ROSDiscover's ⊤ symbol: "I know this is the `USERS_SERVICE_URL`, and whoever composes the system at the next stage can bind it to a concrete URL".

### 5.2 gRPC (new)

gRPC in TypeScript looks like `await userService.getUser({ id: 42 })`. Syntactically it's just a method call — there's nothing structural that says "this is an RPC". What distinguishes it is the *provenance* of the receiver: `userService` was produced by one of three patterns:

1. `clientGrpc.getService<UserService>('UserService')` — the NestJS idiom.
2. `new proto.UserService(addr, creds)` — plain `@grpc/grpc-js`.
3. `createClient(UserServiceDefinition, channel)` — nice-grpc.

So the detector does two things:

- Track variables that look like gRPC stubs (via those three assignment patterns).
- Flag every method call on such a variable as a gRPC connector, except for infrastructure methods like `close`, `waitForReady`.

We **explicitly do not model streaming gRPC** (server-stream, client-stream, bidi). Those behave like pub-sub, and our mandate is call-return only. If a streaming call slips through we emit it as a unary call — the architectural diagram will still show the right endpoints; it just labels a stream like a call.

### 5.3 Redis (new)

Redis commands are easier to detect because the vocabulary is well-defined. `isCallReturnRedisCommand` in `RedisConnector.qll` enumerates the ~80 call-return commands we care about (GET, SET, HGET, LPUSH, ZADD, …) and a **separate** predicate `isPubSubCommand` lists the pub-sub commands we deliberately exclude (PUBLISH, SUBSCRIBE, PSUBSCRIBE, …).

Having the exclusion list written down *explicitly* is the important part. The user said "no pub-sub". Instead of silently filtering, we codified the rule and put a comment on it so anyone reading the code can tell we thought about pub-sub and chose to leave it out.

Redis calls all target a single logical component named `redis` (the shared cache), with the command as the operation and the key as the port label. That matches how ROSDiscover treats the ROS Master — a single shared service.

---

## 6. Why we did not model pub-sub

Publish-subscribe has very different architectural semantics:

- There is no single target — publishers and subscribers are decoupled.
- Well-formedness rules need to compare message *types* across all participants, not just names.
- Bug detection in pub-sub typically needs extra analyses (type checking, subscriber liveness).

The paper's example bug (Autoware's `line_class` → `line` rename) is specifically a pub-sub issue, and the paper spends significant effort on it. Recreating that infrastructure in TypeScript is a separate, larger project. The user asked for call-return only, so we stopped cleanly at that boundary.

`RedisConnector.qll` documents this via the `isPubSubCommand` exclusion list; `GrpcConnector.qll` documents it in the class comment ("UNARY RPC ONLY").

---

## 7. The Python pipeline, plainly

The pipeline is just "read rows, clean them up, draw":

```
CodeQL result file
        │
        │  parser.parse_file(path)
        ▼
List[ConnectorRecord]   ← one frozen dataclass per connector
        │
        │  normalizers.normalise(r)  (per-protocol)
        ▼
List[ConnectorRecord]   ← cleaned: "{FOO}/users" → "/users",
        │                          "KEY(user:*)"  → "user:*"
        │  plantuml_renderer.render(records)
        ▼
diagram.puml
```

`converter.py` at the top is 30 lines of orchestration. Everything interesting lives in the stage modules. That's deliberate — it mirrors the paper's own pipeline figure (Figure 2 in the PDF: *Component Model Recovery ➝ System Composition ➝ Bug Detection*) and makes it easy for someone extending the system to find the place they should touch.

---

## 8. Design trade-offs (so you can argue with me)

**Why abstract class, not interface-style "signature module"?**
CodeQL does support signature modules, but for six predicates on an AST node, an abstract class is a quicker read and works with the `from Connector c` pattern out of the box.

**Why file-level proximity for `getConfigKey` on gRPC/Redis, not taint tracking like Axios?**
Taint-tracking `configService.get(...)` to a `new Client(...)` constructor requires a lot of additional flow steps (through factory providers, DI tokens, options objects). File-level proximity catches the common case in a single line and costs near-zero analysis time. If it turns out to miss too much we can upgrade to proper taint for these connectors without touching anything else.

**Why a heuristic for target-from-URL in Axios?**
Our sample monorepo happens to route `/users` on the users service, `/clubs` on the clubs service, etc. That's a repo convention, not a law. `ServiceIdentification.qll::targetServiceFromUrl` documents the heuristic in one spot. A real deployment that routes differently would override just that predicate.

**Why generate PlantUML and not something sexier (Mermaid, D2)?**
The existing tooling was PlantUML, and keeping the renderer swappable (separate `plantuml_renderer.py` module with no Python-side callers knowing its implementation) means adding a second renderer later is cheap.

**What did we NOT change?**
Nothing in the six sample NestJS services. Nothing in `dataflow6.ql` (kept as a historical reference and a regression benchmark). Nothing in `rules/`. The old converter still works bit-for-bit identically on its old input.

---

## 9. How to run the new pipeline end-to-end

```bash
# 1. Run the unified CodeQL query (replaces dataflow6.ql):
codeql database analyze <db> my-research-project/all_connectors.ql \
  --format=csv --output=my-research-project/tests/final_result.txt

# 2. Convert to PlantUML using the new pipeline:
cd my-research-project
python -m pipeline.converter \
  --input tests/final_result.txt \
  --output ../diagram.puml

# 3. Render the diagram
plantuml ../diagram.puml
```

If you only have Axios results (no gRPC/Redis in your project), the new query will still produce only Axios rows and the output will match the legacy `diagram.puml` — modulo the new edge-style legend. That's the sanity check we care about: the extension is a **strict superset**, not a replacement that could break the existing workflow.

---

## 10. If you want to add a fourth protocol

Let's say tomorrow your repo starts using **NATS** for call-return request/reply. You would:

1. Create `connectors/NatsConnector.qll`, subclass `Connector`, override the six predicates. Use `ExprResolution.qll` for string resolution and `ServiceIdentification.qll` for the caller.
2. Add one line to `all_connectors.ql`: `import connectors.NatsConnector`.
3. Register a normaliser in `pipeline/normalizers.py::NORMALIZERS`.
4. Optional: register a visual style in `pipeline/plantuml_renderer.py::EDGE_STYLE`.

No other files change. No regression risk for Axios/gRPC/Redis. That's the payoff of the refactor.

---

## 11. A detour: CodeQL's binding rules and the errors we had to fix

The first time we shipped the new connectors, CodeQL's compiler lit up with a batch of errors like:

- `'path' is not bound to a value.`
- `'name' is not bound to a value.`
- `could not resolve predicate looksLikeRedisReceiverName/1`
- `asExpr() cannot be resolved for type RedisCall`

Those messages look unrelated, but they're all symptoms of the **same rule** — and understanding that rule is the single most useful thing a sophomore can take away from this project.

### The rule

Every predicate parameter in CodeQL has a **binding mode**. It must be one of:
- **Input-bound** — the caller always supplies it. Declared with `bindingset[x]`.
- **Output-bound** — the predicate's body has a *generator* that produces the values.

A **generator** is something CodeQL can enumerate a finite set from. Examples:
- `x = "auth" or x = "clubs"` — direct equalities, generates two values.
- `knownService(x)` — a predicate whose body itself generates.
- `x = someNode.getName()` — a getter on a bound node, one value per node.

A **filter** tests a value you already have; it does NOT generate. Examples:
- `x.toLowerCase()` — needs `x` to already have a value.
- `x.matches("%foo%")` — same, it tests.
- `not P(x)` — negation needs `x` bound *before* the check.

Mix those up and CodeQL refuses to compile, because a predicate with neither mode has no well-defined semantics (it would have to enumerate the infinite set of all strings).

### How that showed up in our code

**`pathBelongsToService(string path, string service)`** had this body:
```ql
knownService(service) and
(path.matches(service + "/%") or path.matches("%/" + service + "/%"))
```
- `knownService(service)` is a generator for `service` ✓
- `path.matches(...)` is a filter for `path` ✗ — no generator binds `path`.

So `path` has neither input nor output mode. Fix: add `bindingset[path]` to declare it as input-mode. All our callers already pass `f.getRelativePath()` (bound), so the annotation is honest — we just hadn't told CodeQL.

**Three Redis predicates** (`looksLikeRedisReceiverName`, `isCallReturnRedisCommand`, `isPubSubCommand`) all started with `exists(string lower | lower = name.toLowerCase() | ...)`. The `.toLowerCase()` call is a filter on `name`. Same fix: `bindingset[name]`.

**The cascading errors** (`asExpr() cannot be resolved`, `could not resolve looksLikeRedisReceiverName/1`) weren't real bugs in our code — they were CodeQL reporting downstream symbols it couldn't type-check because the upstream predicates failed to compile. Fixing the root binding errors makes them disappear for free. This is worth remembering: when you get ten CodeQL errors, fix the earliest one first and re-run; half the rest usually evaporate.

### One more trap: `not exists(EXPR)`

Our Redis `getEndpoint` had:
```ql
not exists(this.getArgument(0)) and result = "KEY(*)"
```
This looks like "there is no first argument". It doesn't compile. `exists(...)` in CodeQL must quantify over a **typed variable** — you can't just feed it an expression. The correct form is:
```ql
not exists(Expr firstArg | firstArg = this.getArgument(0)) and result = "KEY(*)"
```
Same meaning; this time CodeQL can introduce the quantifier variable and reason about it.

### The mental model

If you remember just one thing from this section: **CodeQL is a database query language, not a procedural language**. Every predicate must describe a finite, enumerable relation. When you hit "not bound to a value", ask: *at this point in the body, what finite set of values can my parameter take, and where does that set come from?* If your answer is "whatever the caller passes", write `bindingset[param]`. If it's "the body enumerates them", make sure the body actually has equalities or generator predicates on the parameter. Filters alone are never enough.

## 12. A second detour: when the query ran out of memory

After the binding fixes, the analyser compiled cleanly — and then promptly OOM'd on a real repo. The lesson is worth its own section because it's one every static-analysis beginner meets, and the fix is not "give CodeQL more RAM".

### The symptom

```
Running queries.
CodeQL is out of memory. You may need to adjust the memory used by CodeQL
using the --ram option.
```

### The cause: a too-generous candidate set

The `RedisCall` characteristic predicate originally looked like this:

```ql
RedisCall() {
  isCallReturnRedisCommand(this.getMethodName()) and    // "get", "set", "exists", ...
  not isPubSubCommand(this.getMethodName()) and
  (
    fileUsesRedis(this.getFile())                        // cheap gate
    or
    exists(string recvName | ... | looksLikeRedisReceiverName(recvName))   // name heuristic
  )
}
```

Look at the allow-list of Redis commands we accepted: `get`, `set`, `exists`, `keys`, `del`, `watch`, `type`, `scan`, `multi`, `eval`. These are **extremely common JavaScript method names**. Every `Map.get`, `Set.has`, `URL.searchParams.get`, `EventEmitter.on`, custom getter you can think of — each one is a *candidate* that the query has to evaluate the filter on.

In the codebase at hand there are no Redis imports, so the `fileUsesRedis` side of the `or` is always false. CodeQL then goes to the second side, computes `getReceiver().getName()` (or `.getPropertyName()`) for every candidate, and joins against the name heuristic. That intermediate join is what blew the memory budget.

### The fix: gate first, filter later

Reorder the characteristic predicate so the **cheap and precise gate runs first**:

```ql
RedisCall() {
  fileUsesRedis(this.getFile()) and                       // <- gate
  isCallReturnRedisCommand(this.getMethodName()) and
  not isPubSubCommand(this.getMethodName())
}
```

Now on a Redis-free codebase, the gate is false for every file, so the predicate produces zero instances in near-zero time. On a codebase that does use Redis, we get exactly the same detection as before for the imported-and-used case — we only sacrifice detection of Redis clients that reach a file purely through DI without ever being imported into it. For NestJS specifically that case is rare (modules importing Redis usually import the client's type for typing), and a more targeted detector can be added later if real projects need it.

There's a second performance edit worth noting: I deleted the `exists(string lower | lower = name.toLowerCase() | ...)` shape from the three Redis predicates and replaced it with direct lowercase equalities. Node's Redis clients only expose lowercase methods at runtime, so there's no coverage loss. The payoff: `isCallReturnRedisCommand` now acts as a **generator** (a small table of ~80 literal strings that CodeQL can join against `MethodCallExpr.getMethodName()`) instead of a **filter** (which requires `bindingset[name]` and is applied one candidate at a time). Generators are dramatically faster in CodeQL's evaluator.

### And one more: memoising the flow relation

The `AxiosCall.getConfigKey` method had a positive and a negative branch, each running the same taint-flow join:

```ql
override string getConfigKey() {
  exists(DataFlow::Node source, DataFlow::Node sink, MethodCallExpr mc |
    ConfigToAxios::flow(source, sink) and ...
    result = mc.getAnArgument().(StringLiteral).getValue()
  )
  or
  not exists(DataFlow::Node source, DataFlow::Node sink |
    ConfigToAxios::flow(source, sink) and ...
  ) and result = ""
}
```

CodeQL *could* memoise the shared sub-query, but making the sharing explicit is friendlier: hoist the flow-to-this-sink check into its own predicate and let both branches call it.

```ql
override string getConfigKey() {
  configKeyFlowsTo(result, this)
  or
  result = "" and not configKeyFlowsTo(_, this)
}

private predicate configKeyFlowsTo(string key, AxiosCall call) { ... }
```

The relation is now named, and CodeQL materialises it exactly once.

### Heuristics for the sophomore reader

When a CodeQL query OOMs, don't reach for `--ram` first. Ask:

1. **Is my characteristic predicate gated by something cheap and precise?** The rule of thumb is: your first conjunct should eliminate ~99% of candidates. Library imports, file extensions, receiver identity, class-hierarchy checks are all good first gates.
2. **Do any of my predicates look like filters when they could be generators?** Equality on a literal string is a generator. `x.toLowerCase() = "foo"` is a filter. If you can remove a call chain on the parameter, do.
3. **Am I running the same expensive sub-query twice in one predicate?** Hoist it into a named predicate so CodeQL has an obvious caching opportunity.
4. **Does my characteristic predicate order its clauses from cheap-and-precise to expensive?** CodeQL's join planner is good but not magical; putting the gate first helps it.

The OOM disappeared after applying the first and second heuristics. The third (hoisting the flow predicate) is preventative — it made the Axios side cheaper even though it wasn't the direct cause of the blow-up.

## 13. Where the research paper pushed us further

Two things from the paper we haven't implemented yet but would be the natural next steps:

- **Rule checking.** ROSDiscover's stage 3 expresses architectural rules in first-order logic and flags violations. We produce the graph but don't yet check anything on it. A reasonable starting rule for our world: *every `configService.get("X_SERVICE_URL")` call on one side must have a matching `app.listen()` binding `X` on the other*. That mirrors the "dangling publisher / subscriber" rule in the paper.
- **Handwritten component models.** The paper's 15 handwritten models for the ROS core library cover gaps in the static analysis. Our equivalent would be handwritten models for third-party NestJS interceptors or custom transport adapters that static analysis can't see through. The place to plug them in is a new `models/` directory with one YAML file per component.

Both are additive and fit the same layered structure — which is the whole point of the design.

---

## Appendix: troubleshooting checklist for CodeQL compile errors

| Symptom (error text) | Likely cause | First thing to try |
|---|---|---|
| `'X' is not bound to a value.` | Parameter `X` has no generator and no `bindingset`. | Add `bindingset[X]` if the caller always supplies it; otherwise add a generator to the body. |
| `could not resolve predicate P/n` | `P` failed to compile earlier in the file. | Scroll up — fix the first binding error you see. |
| `asExpr() / getFoo() cannot be resolved for type Y` | `Y` failed to compile, so its type isn't resolvable. | Same as above — cascading. |
| `getModuleSpecifier() cannot be resolved for type ...ImportDeclaration` | An auto-fix / manual edit introduced a non-existent method. | Revert to `getImportedPath().getValue()`. |
| `predicate 'getImportedPath' has been deprecated` (warning) | Safe to ignore, or centralise the call in one helper for easy migration later. | Keep using it; the method still works. |
| `not exists(SOME_EXPR)` syntax error | Bare expression inside `exists()`. | Use `not exists(Type v | v = SOME_EXPR)`. |
