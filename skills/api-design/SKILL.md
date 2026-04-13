---
name: api-design
description: Guidelines for REST API design including resource naming, HTTP methods, status codes, versioning, validation with Zod, and OpenAPI spec generation.
sub-team: architecture
type: flexible
---

# API Design

## When to Apply

Use this skill when designing REST APIs, defining service contracts, or reviewing API endpoints. Flexible -- adapt conventions to project needs, but follow the checklist.

## REST Resource Naming

1. Use plural nouns for collections: `/users`, `/orders`, `/products`
2. Use nested resources for relationships: `/users/:id/orders`
3. NEVER use verbs in URLs -- use HTTP methods instead (`POST /orders`, not `POST /create-order`)
4. Use kebab-case for multi-word resources: `/order-items`, not `/orderItems`
5. Keep nesting to maximum 2 levels deep: `/users/:id/orders` (not `/users/:id/orders/:orderId/items/:itemId`)
6. Use query parameters for filtering, sorting, pagination: `/users?role=admin&sort=name&page=2`

## HTTP Methods

1. `GET` -- Read (idempotent, no side effects, cacheable)
2. `POST` -- Create a new resource (not idempotent)
3. `PUT` -- Full replacement of a resource (idempotent)
4. `PATCH` -- Partial update of a resource (not necessarily idempotent)
5. `DELETE` -- Remove a resource (idempotent)
6. NEVER use `GET` for operations with side effects
7. ALWAYS return the created/updated resource in the response body for POST/PUT/PATCH

## Status Codes

1. `200` -- Success (GET, PUT, PATCH, DELETE)
2. `201` -- Created (POST when resource is created)
3. `204` -- No Content (DELETE when nothing to return)
4. `400` -- Bad Request (validation errors, malformed input)
5. `401` -- Unauthorized (missing or invalid authentication)
6. `403` -- Forbidden (authenticated but not authorized)
7. `404` -- Not Found (resource does not exist)
8. `409` -- Conflict (duplicate resource, version conflict)
9. `422` -- Unprocessable Entity (valid syntax but semantic error)
10. `429` -- Too Many Requests (rate limited)
11. `500` -- Internal Server Error (unexpected failures only)
12. NEVER return 200 with an error body -- use proper status codes

## Error Response Format

ALWAYS use a consistent error format:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human-readable description",
    "details": [
      { "field": "email", "message": "Must be a valid email address" }
    ]
  }
}
```

## Versioning Strategy

1. Prefer URL path versioning: `/api/v1/users`, `/api/v2/users`
2. Increment the major version only for breaking changes
3. Non-breaking additions (new fields, new endpoints) do NOT require a version bump
4. Support at most 2 versions simultaneously (current + previous)
5. Deprecation: announce 3 months before removing old version

## Request/Response Validation

1. ALWAYS validate request bodies and query parameters at the API boundary
2. Use Zod for TypeScript projects:

```typescript
const CreateUserSchema = z.object({
  name: z.string().min(1).max(100),
  email: z.string().email(),
  role: z.enum(["admin", "user"]).default("user"),
});
```

3. Return 400 with field-level errors on validation failure
4. NEVER trust client input -- validate even if the frontend already validates

## OpenAPI Specification

1. Generate OpenAPI 3.0+ specs from code (Zod schemas -> OpenAPI via `zod-to-openapi`)
2. Keep the spec in version control: `docs/openapi.yaml`
3. Include examples for every endpoint
4. Use the spec as the contract for frontend-backend development

## Contract-First Design

1. Define the API contract (OpenAPI spec) before implementing
2. Both consumer and provider teams agree on the contract
3. Use contract tests to verify implementation matches the spec
4. NEVER change a published contract without versioning

## Pagination

1. Use cursor-based pagination for large datasets: `?cursor=abc123&limit=20`
2. Use offset-based pagination only for small, stable datasets: `?page=2&limit=20`
3. ALWAYS include pagination metadata in responses:

```json
{
  "data": [...],
  "pagination": { "next_cursor": "abc456", "has_more": true }
}
```

## Rate Limiting

1. Return `429 Too Many Requests` with `Retry-After` header
2. Include rate limit headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`

## Design Checklist

1. [ ] All resources use plural nouns, no verbs in URLs
2. [ ] Correct HTTP methods for each operation
3. [ ] Appropriate status codes (no 200-with-error-body)
4. [ ] Consistent error response format across all endpoints
5. [ ] Request validation with Zod at the API boundary
6. [ ] OpenAPI spec generated and committed
7. [ ] Pagination implemented for list endpoints
8. [ ] Rate limiting configured
9. [ ] Versioning strategy decided and documented

## Red Flags

- Verbs in URL paths (`/createUser`) -- restructure to resource + HTTP method
- 200 status with error body -- use proper error status codes
- No input validation at API layer -- add Zod schemas immediately
- Missing OpenAPI spec -- generate from existing code or write contract first
