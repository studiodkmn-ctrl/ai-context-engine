# 🧪 Testing — /Users/adnandikmen/Desktop/test-kontext
> **Test strategy, patterns, and conventions for this codebase.**
> Load for: writing tests, test debugging, CI failures.
> Last updated: 2026-04-14

---

## Stack
```
Unit / Integration:   Vitest
Frontend components:  Vitest + @testing-library/react
E2E:                  Playwright
API routes:           Vitest + supertest (or httpx for Python)
Mocking:              vi.mock() / vi.fn()
Coverage tool:        Vitest --coverage
Coverage goal:        ≥80% on src/lib/ and src/app/api/
```

---

## Naming Convention
```
Unit test file:        [filename].test.ts       (co-located with source)
Integration test:      [filename].integration.test.ts
E2E test:              tests/e2e/[feature].spec.ts
Test function:         it('should [action] when [condition]', ...)
Describe block:        describe('[ComponentName or function]', ...)
```

---

## Mock Strategy
```
External APIs:         Always mock — never call real endpoints in tests
Database (Prisma):     Mock via vi.mock('../lib/prisma') with prismaMock factory
Auth session:          Mock auth() to return test session object
Date/Time:             Use vi.setSystemTime() — never rely on real clock
File system:           Mock with memfs or vi.mock('fs')
```

---

## Standard Patterns

### API Route Test
```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { POST } from '@/app/api/items/route'

vi.mock('@/lib/prisma', () => ({
  default: { item: { create: vi.fn() } }
}))
vi.mock('@/lib/auth', () => ({
  auth: vi.fn(() => ({ user: { id: 'test-user-id' } }))
}))

describe('POST /api/items', () => {
  it('should create item when authenticated', async () => {
    const req = new Request('http://localhost/api/items', {
      method: 'POST',
      body: JSON.stringify({ name: 'Test Item' })
    })
    const res = await POST(req)
    expect(res.status).toBe(201)
  })

  it('should return 401 when not authenticated', async () => {
    vi.mocked(auth).mockResolvedValueOnce(null)
    const req = new Request('http://localhost/api/items', { method: 'POST' })
    const res = await POST(req)
    expect(res.status).toBe(401)
  })
})
```

### Component Test
```typescript
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, it, expect } from 'vitest'
import { Button } from '@/components/ui/button'

describe('Button', () => {
  it('should call onClick when clicked', async () => {
    const onClick = vi.fn()
    render(<Button onClick={onClick}>Click me</Button>)
    await userEvent.click(screen.getByRole('button'))
    expect(onClick).toHaveBeenCalledOnce()
  })
})
```

---

## What NOT to Test
```
✗ Implementation details (internal state, private methods)
✗ Third-party library internals (trust Prisma works)
✗ Snapshot tests for complex components (too brittle)
✗ Styling (CSS-in-JS output, classnames)
```

---

## Running Tests
```bash
vitest                    # watch mode
vitest run                # single run (CI)
vitest run --coverage     # with coverage report
vitest run src/app/api/   # specific folder
playwright test           # E2E
```

---
> WRITEBACK RULE: New test pattern established → add to "Standard Patterns" section.
> If stack changes (new test runner) → update "Stack" section and add gotcha to _gotchas.md.
