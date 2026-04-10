# Architecture

## Overview

<!-- What the system does in 2-3 sentences. Who uses it and what problem it solves. -->

## Architecture Diagram

```
┌─────────────────────────────────┐
│         Presentation            │  CLI / HTTP / UI
└────────────────┬────────────────┘
                 │
┌────────────────▼────────────────┐
│         Application             │  Use cases, orchestration
└────────────────┬────────────────┘
                 │
┌────────────────▼────────────────┐
│           Domain                │  Entities, business rules
└────────────────┬────────────────┘
                 │
┌────────────────▼────────────────┐
│        Infrastructure           │  DB, external APIs, adapters
└─────────────────────────────────┘
```

## Layers

| Layer | Responsibility | Allowed Dependencies |
|---|---|---|
| Domain | Entities, value objects, domain services | None |
| Application | Use cases, ports | Domain |
| Infrastructure | Adapters, repositories, external clients | Application, Domain |
| Presentation | Controllers, views, CLI | Application |

## Key Components

| Component | Layer | Purpose |
|---|---|---|
| `ComponentName` | domain / application / infrastructure / presentation | What it does |

## Data Flow

1. Request enters at Presentation layer.
2. Presentation calls Application use case.
3. Use case coordinates Domain logic.
4. Infrastructure adapters handle persistence and external calls.
5. Result propagates back up to the caller.

## External Dependencies

| Dependency | Purpose | Version |
|---|---|---|
| Library / Service | Why it is used | x.y.z |

## Related ADRs

- [ADR-001: Title](docs/adrs/001-title.md)
