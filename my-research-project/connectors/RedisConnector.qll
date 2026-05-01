/**
 * RedisConnector.qll
 *
 * Detects call-return Redis commands in TypeScript codebases.
 *
 * WHY A DEDICATED MODULE FOR A "DATABASE":
 *   In a ROSDiscover-style architecture view, Redis is a shared component
 *   that several microservices talk to. The call from service A to Redis
 *   is a connector just like a REST call from A to B; the distinction is
 *   only in what is served on the other side.
 *
 * SCOPE - CALL-RETURN ONLY:
 *   Redis has two major interaction styles:
 *     1. Commands (GET/SET/HGET/...) - synchronous request/response.
 *     2. Pub-sub (PUBLISH/SUBSCRIBE/PSUBSCRIBE/...) - topic-style.
 *   Per the project requirement we model ONLY style 1. The
 *   `isPubSubCommand` predicate below enumerates the forbidden commands
 *   so we can be explicit about what we exclude rather than silently
 *   missing them.
 *
 *   We also exclude streaming commands like `SUBSCRIBE` - Redis Streams
 *   (`XREAD`, `XADD`) are on the boundary; we include write commands
 *   (`XADD`) as call-return but exclude `XREAD BLOCK` style loops.
 */

import javascript
import lib.Connector
import lib.ExprResolution
import lib.ServiceIdentification

/**
 * Imports that indicate a Redis client is in use.
 * Matches the two dominant Node libraries and the NestJS wrappers around
 * them.
 */
private predicate fileUsesRedis(File f) {
  exists(ImportDeclaration id | id.getFile() = f |
    id.getImportedPath().getValue() = "redis" or
    id.getImportedPath().getValue() = "ioredis" or
    id.getImportedPath().getValue() = "@liaoliaots/nestjs-redis" or
    id.getImportedPath().getValue() = "@nestjs-modules/ioredis" or
    id.getImportedPath().getValue() = "@songkeys/nestjs-redis" or
    id.getImportedPath().getValue() = "cache-manager-redis-store"
  )
}

/**
 * The set of Redis commands we treat as call-return connectors.
 *
 * WHY A CLOSED SET:
 *   Redis has hundreds of commands and grows. A closed set is safer than
 *   matching every `client.X(...)` because it:
 *     1) Excludes pub-sub explicitly (see `isPubSubCommand`).
 *     2) Excludes infrastructure calls (`connect`, `quit`, `on`, `ping`).
 *     3) Gives a clear affordance for authors to add more commands when
 *        they need them.
 *
 * WHY ONLY LOWERCASE (NO `toLowerCase()` CALL):
 *   Node Redis v4 and ioredis expose their commands exclusively as
 *   lowercase methods (`redis.get`, `redis.set`, ...). Calling
 *   `redis.GET(...)` would not even run at runtime. Matching only
 *   lowercase therefore loses no coverage and - crucially - lets CodeQL
 *   evaluate this predicate as a pure generator (small join table of
 *   literal strings) instead of a filter-over-`toLowerCase`. The old
 *   filter form required `bindingset[name]` and was applied per
 *   candidate method call; the join form is materialised once and
 *   scans thousands of times faster on large codebases.
 */
private predicate isCallReturnRedisCommand(string name) {
  // String / key commands
  name = "get" or name = "set" or name = "setex" or name = "setnx" or
  name = "getset" or name = "mget" or name = "mset" or name = "append" or
  name = "strlen" or name = "incr" or name = "incrby" or name = "decr" or
  name = "decrby" or name = "del" or name = "unlink" or name = "exists" or
  name = "expire" or name = "expireat" or name = "persist" or name = "ttl" or
  name = "keys" or name = "scan" or name = "type" or name = "rename" or
  // Hash
  name = "hget" or name = "hset" or name = "hmget" or name = "hmset" or
  name = "hgetall" or name = "hdel" or name = "hexists" or name = "hincrby" or
  name = "hlen" or name = "hkeys" or name = "hvals" or name = "hscan" or
  // List
  name = "lpush" or name = "rpush" or name = "lpop" or name = "rpop" or
  name = "lrange" or name = "llen" or name = "lindex" or name = "linsert" or
  name = "lset" or name = "lrem" or name = "ltrim" or
  // Set
  name = "sadd" or name = "srem" or name = "smembers" or name = "sismember" or
  name = "scard" or name = "sinter" or name = "sunion" or name = "sdiff" or
  name = "sscan" or name = "spop" or name = "srandmember" or
  // Sorted set
  name = "zadd" or name = "zrem" or name = "zrange" or name = "zrevrange" or
  name = "zrangebyscore" or name = "zscore" or name = "zincrby" or
  name = "zcard" or name = "zcount" or name = "zscan" or name = "zrank" or
  // Streams (write-side only - reads can be blocking/streaming)
  name = "xadd" or name = "xlen" or name = "xdel" or
  // Transactions / pipelines
  name = "multi" or name = "exec" or name = "discard" or name = "watch" or
  name = "unwatch" or
  // Server / scripting that still return synchronously
  name = "eval" or name = "evalsha"
}

/**
 * Redis pub-sub commands that we deliberately EXCLUDE.
 * Enumerated here (rather than just omitted from the allow-list) so the
 * exclusion is obvious to future readers and so we can guard against
 * accidentally matching them via another predicate.
 */
private predicate isPubSubCommand(string name) {
  name = "publish" or name = "subscribe" or name = "unsubscribe" or
  name = "psubscribe" or name = "punsubscribe" or name = "pubsub"
}

/**
 * A Redis command invocation, e.g. `await redis.get("user:42")`.
 *
 * WE DO NOT FOLLOW METHOD CHAINS FOR `MULTI`:
 *   Redis pipelines often look like `redis.multi().set(...).exec()`. Each
 *   link is a separate MethodCallExpr, so we'll emit one connector per
 *   link naturally. That's the right granularity for architectural
 *   recovery: each command still targets the same Redis component and the
 *   operation name is preserved.
 */
class RedisCall extends Connector, MethodCallExpr {
  RedisCall() {
    // Precision gate FIRST: require the enclosing file to import a
    // Redis client. Without this, the commonness of names like `get`,
    // `set`, `exists`, `keys` makes every `Map.get`, `Set.has`,
    // `URL.searchParams.get` etc. a candidate that CodeQL has to
    // filter, blowing up memory on non-Redis codebases. With the gate,
    // the candidate set is empty on Redis-free repos at essentially
    // zero evaluation cost.
    //
    // TRADE-OFF:
    //   We lose the case where a Redis client is injected via DI and
    //   the consuming file never imports the client library. In NestJS
    //   this is rare (modules that use Redis almost always import the
    //   client type for typing). Authors who need to recover that case
    //   can relax this gate locally.
    fileUsesRedis(this.getFile()) and
    isCallReturnRedisCommand(this.getMethodName()) and
    not isPubSubCommand(this.getMethodName())
  }

  override string getProtocol() { result = "redis" }

  override string getOperation() { result = this.getMethodName().toUpperCase() }

  override string getCallerService() { result = callerServiceForExpr(this) }

  /**
   * Every Redis call targets the logical "redis" component. We don't try
   * to distinguish per-instance Redis clusters here: the architectural
   * view treats Redis as one shared resource, matching how the paper
   * treats ROS Master as a single logical entity.
   */
  override string getTargetService() { result = "redis" }

  /**
   * Endpoint is the RESOLVED key argument when one is present, wrapped in
   * a `KEY(...)` marker so the renderer can visually distinguish keys
   * from REST paths and gRPC method-paths.
   *
   * For commands with no key (e.g. `MULTI`, `EXEC`) we return a marker so
   * the row still renders.
   */
  override string getEndpoint() {
    exists(Expr firstArg |
      firstArg = this.getArgument(0) and
      result = "KEY(" + resolveExprValue(firstArg) + ")"
    )
    or
    // No first argument (e.g. `MULTI`, `EXEC`, pipeline terminators).
    // Use a quantified existence check because `not exists(EXPR)` without
    // a binding variable is not valid QL.
    not exists(Expr firstArg | firstArg = this.getArgument(0)) and
    result = "KEY(*)"
  }

  /**
   * Config key is the env-var that named the Redis host (e.g.
   * `REDIS_HOST`, `REDIS_URL`). We use file-level proximity for the same
   * reason the gRPC connector does: the host typically reaches the client
   * via DI/factory indirection, so tight-scope taint tracking would miss
   * the common case.
   */
  override string getConfigKey() {
    exists(MethodCallExpr cfgGet |
      cfgGet.getFile() = this.getFile() and
      cfgGet.getMethodName() = "get" and
      cfgGet.getReceiver().(PropAccess).getPropertyName().toLowerCase().matches("%config%") and
      result = cfgGet.getArgument(0).(StringLiteral).getValue()
    )
    or
    not exists(MethodCallExpr cfgGet |
      cfgGet.getFile() = this.getFile() and
      cfgGet.getMethodName() = "get" and
      cfgGet.getReceiver().(PropAccess).getPropertyName().toLowerCase().matches("%config%")
    ) and
    result = ""
  }
}
