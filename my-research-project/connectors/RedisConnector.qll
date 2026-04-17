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
 * Heuristic: variables that hold a Redis client.
 *
 * WHY A NAMING HEURISTIC IN ADDITION TO IMPORT CHECK:
 *   The file-level import check is not always enough: some codebases hide
 *   Redis behind a DI token and the file that USES the client doesn't
 *   re-import the library. Matching names like `redis`, `cache`,
 *   `redisClient`, `ioredis` catches these without relying on type info.
 *
 *   False positives (a variable named `redis` that is not actually a
 *   Redis client) are filtered by the command-name check below: if the
 *   called method isn't a Redis command, the sink is rejected.
 */
private predicate looksLikeRedisReceiverName(string name) {
  exists(string lower | lower = name.toLowerCase() |
    lower = "redis" or lower = "redisclient" or lower = "ioredis" or
    lower = "cache" or lower = "cacheclient" or lower.matches("%redis%")
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
 *   Methods on Node Redis clients are lower-case (`redis` v4 style). We
 *   match case-insensitively below so both `get` and `GET` are accepted.
 */
private predicate isCallReturnRedisCommand(string name) {
  exists(string lower | lower = name.toLowerCase() |
    // String / key commands
    lower = "get" or lower = "set" or lower = "setex" or lower = "setnx" or
    lower = "getset" or lower = "mget" or lower = "mset" or lower = "append" or
    lower = "strlen" or lower = "incr" or lower = "incrby" or lower = "decr" or
    lower = "decrby" or lower = "del" or lower = "unlink" or lower = "exists" or
    lower = "expire" or lower = "expireat" or lower = "persist" or lower = "ttl" or
    lower = "keys" or lower = "scan" or lower = "type" or lower = "rename" or
    // Hash
    lower = "hget" or lower = "hset" or lower = "hmget" or lower = "hmset" or
    lower = "hgetall" or lower = "hdel" or lower = "hexists" or lower = "hincrby" or
    lower = "hlen" or lower = "hkeys" or lower = "hvals" or lower = "hscan" or
    // List
    lower = "lpush" or lower = "rpush" or lower = "lpop" or lower = "rpop" or
    lower = "lrange" or lower = "llen" or lower = "lindex" or lower = "linsert" or
    lower = "lset" or lower = "lrem" or lower = "ltrim" or
    // Set
    lower = "sadd" or lower = "srem" or lower = "smembers" or lower = "sismember" or
    lower = "scard" or lower = "sinter" or lower = "sunion" or lower = "sdiff" or
    lower = "sscan" or lower = "spop" or lower = "srandmember" or
    // Sorted set
    lower = "zadd" or lower = "zrem" or lower = "zrange" or lower = "zrevrange" or
    lower = "zrangebyscore" or lower = "zscore" or lower = "zincrby" or
    lower = "zcard" or lower = "zcount" or lower = "zscan" or lower = "zrank" or
    // Streams (write-side only - reads can be blocking/streaming)
    lower = "xadd" or lower = "xlen" or lower = "xdel" or
    // Transactions / pipelines
    lower = "multi" or lower = "exec" or lower = "discard" or lower = "watch" or
    lower = "unwatch" or
    // Server / scripting that still return synchronously
    lower = "eval" or lower = "evalsha"
  )
}

/**
 * Redis pub-sub commands that we deliberately EXCLUDE.
 * Enumerated here (rather than just omitted from the allow-list) so the
 * exclusion is obvious to future readers and so we can guard against
 * accidentally matching them via another predicate.
 */
private predicate isPubSubCommand(string name) {
  exists(string lower | lower = name.toLowerCase() |
    lower = "publish" or lower = "subscribe" or lower = "unsubscribe" or
    lower = "psubscribe" or lower = "punsubscribe" or lower = "pubsub"
  )
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
    isCallReturnRedisCommand(this.getMethodName()) and
    not isPubSubCommand(this.getMethodName()) and
    (
      fileUsesRedis(this.getFile())
      or
      // Even without an explicit import (because the client arrived via
      // DI), a receiver name that looks like a Redis handle is enough
      // when combined with a real Redis command.
      exists(string recvName |
        recvName = this.getReceiver().(Identifier).getName() or
        recvName = this.getReceiver().(PropAccess).getPropertyName()
      |
        looksLikeRedisReceiverName(recvName)
      )
    )
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
    not exists(this.getArgument(0)) and
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
