/**
 * Connector.qll
 *
 * Abstract base class for every call-return connector we recover.
 *
 * WHY AN ABSTRACT BASE CLASS:
 *   ROSDiscover models architecture as a typed graph of components joined
 *   by connectors. Each connector kind (topic, service, action) exposes the
 *   SAME small set of architectural properties: who the caller is, what
 *   role it plays, what endpoint identifies it.
 *
 *   We mirror that design choice: every connector module (Axios, gRPC,
 *   Redis, ...) extends this single base class and overrides six
 *   predicates. The top-level query then asks "give me every `Connector`"
 *   and doesn't need to know which protocol produced each row.
 *
 *   Without this abstraction, adding a new protocol would mean editing the
 *   top-level query, the renderer AND every downstream consumer. With it,
 *   a new protocol is a pure addition - you write a new `.qll` that extends
 *   `Connector` and the existing query picks it up automatically.
 *
 * WHY WE ONLY MODEL CALL-RETURN:
 *   The user's requirement explicitly excludes publish-subscribe. Every
 *   subclass below represents a synchronous (or request/response
 *   asynchronous) call - NOT topic-style broadcasts. Redis PUBSUB, NATS,
 *   Kafka and similar patterns are intentionally not modelled here.
 */

import javascript

/**
 * A location in source code that represents a single call-return connector
 * invocation (e.g. one `axios.get(...)`, one gRPC unary call, one
 * `redis.get(...)`).
 *
 * Subclasses specialise `this` to the concrete AST node they detect and
 * override the six architectural predicates below.
 */
abstract class Connector extends Locatable {
  /**
   * Protocol family for this connector.
   * Stable lowercase tokens ("rest", "grpc", "redis", ...) so the Python
   * pipeline can dispatch on them without parsing free-form strings.
   */
  abstract string getProtocol();

  /**
   * The operation name (HTTP method / gRPC method / Redis command).
   * Kept as a string because the three protocols use disjoint vocabularies
   * and a shared enum would be more brittle than helpful.
   */
  abstract string getOperation();

  /**
   * The caller microservice (which workspace folder made this call).
   * Delegates to `ServiceIdentification.qll` in every subclass so the
   * attribution rule lives in ONE place.
   */
  abstract string getCallerService();

  /**
   * The target service / component this call is directed at.
   * May be `"unknown-service"` when static analysis cannot resolve it -
   * ROSDiscover's ⊤-style over-approximation.
   */
  abstract string getTargetService();

  /**
   * The resolved endpoint identifier (URL path, gRPC `service.method`,
   * Redis key pattern, ...). Used both as a port label on the target
   * component and to detect misconfigurations where two sides disagree.
   */
  abstract string getEndpoint();

  /**
   * The configuration key that named the target, if any
   * (e.g. `USERS_SERVICE_URL`). Empty string when the call does not read
   * its target from configuration.
   *
   * WHY WE CARE:
   *   Misconfiguration bugs in the paper typically manifest as a rename in
   *   one place but not the other. Capturing the config key gives the rule
   *   checker a join point to compare producer vs. consumer.
   */
  abstract string getConfigKey();
}
