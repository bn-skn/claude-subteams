---
name: service-boundaries
description: Decision framework for service decomposition -- when to split vs keep together, bounded contexts, data ownership, and communication patterns.
---

# Service Boundaries

## When to Apply

Use this skill when deciding monolith vs microservices, designing new services, splitting an existing service, or reviewing inter-service communication. Flexible -- the right boundary depends on team size, scale, and complexity.

## Decision Framework: Split vs Keep Together

### Split when ALL of these are true:

1. The component has a distinct bounded context with its own domain language
2. The component has different scaling requirements from the rest
3. The component can be deployed independently without coordinated releases
4. The team working on it is (or will be) separate
5. The data it owns is not tightly coupled to other components

### Keep together when ANY of these are true:

1. Components share the same data and transactions frequently
2. Splitting would require distributed transactions
3. The team is small (fewer than 5 developers)
4. The domain boundaries are unclear or still evolving
5. You are optimizing for development speed over operational complexity

### The default answer is: keep together. Split only with evidence.

## Bounded Contexts

1. Each service owns exactly one bounded context
2. Define the ubiquitous language for each context (same word can mean different things in different contexts)
3. Map context boundaries explicitly before splitting:
   - **User** in Auth context = credentials + permissions
   - **User** in Billing context = payment methods + invoices
   - These are different models, not shared entities
4. NEVER share domain models across service boundaries -- each service defines its own
5. Use Anti-Corruption Layers (ACL) to translate between contexts

## Data Ownership

1. Each service MUST own its data -- no shared databases
2. NEVER allow direct database access from another service
3. Data is exposed only through the service's API
4. If two services need the same data, one owns it and the other requests it
5. For read-heavy cross-service data, use events to maintain local read replicas
6. Accept eventual consistency between services -- strong consistency within a service

## Communication Patterns

### Synchronous (REST / gRPC)

Use when:
1. The caller needs an immediate response
2. The operation is simple request-response
3. Latency requirements are strict

Rules:
1. ALWAYS set timeouts on synchronous calls
2. Implement circuit breakers for external service calls
3. Use retries with exponential backoff for transient failures
4. NEVER chain more than 3 synchronous calls (A -> B -> C -> D is too deep)

### Asynchronous (Events / Message Queue)

Use when:
1. The caller does not need an immediate response
2. The operation can be processed later
3. You need to decouple services for resilience
4. Multiple consumers need to react to the same event

Rules:
1. Events are immutable facts -- describe what happened, not what to do
2. Use past tense for event names: `OrderPlaced`, `UserRegistered`
3. Include enough data in the event for consumers to act without calling back
4. Design for idempotent consumers -- events may be delivered more than once
5. NEVER use events for request-response patterns

## Shared vs Separate Databases

| Approach | When to Use | Trade-offs |
|----------|------------|------------|
| **Separate databases** | Default for microservices | Data isolation, independent scaling, operational complexity |
| **Shared database, separate schemas** | Transitioning from monolith | Easier migration, some coupling remains |
| **Shared database, shared schema** | Monolith only | Simple, but tight coupling -- not for microservices |

1. ALWAYS start with separate databases for new microservices
2. Shared database is acceptable only during monolith-to-microservice migration (temporary)
3. NEVER share a schema between independently deployed services

## API Gateway

1. Use an API gateway for external-facing services
2. The gateway handles: routing, authentication, rate limiting, request transformation
3. NEVER put business logic in the gateway
4. Internal service-to-service calls bypass the gateway

## Service Boundary Checklist

1. [ ] Bounded context identified and documented
2. [ ] Ubiquitous language defined for the context
3. [ ] Data ownership is clear -- one owner per data entity
4. [ ] Communication pattern chosen (sync vs async) with rationale
5. [ ] No shared databases between independently deployed services
6. [ ] Circuit breakers and timeouts configured for sync calls
7. [ ] Events are idempotent and use past-tense naming
8. [ ] No more than 3 levels of synchronous call chains
9. [ ] Decision documented in an ADR

## Red Flags

- Shared database between independently deployed services -- split or merge the services
- Synchronous call chain deeper than 3 levels -- introduce async events
- Service that cannot be deployed independently -- it is not a real service boundary
- Domain models shared across services via a common library -- use ACL instead
- Splitting services when the team is small and boundaries are unclear -- keep the monolith
- Events used for request-response -- use sync calls instead
