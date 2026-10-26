# Proposed MVP Decision Register

**Status:** Proposed operational rules for review; not approved product requirements. These rules describe application behavior and are not accounting or tax advice. Obtain qualified professional advice before using reports for accounting, tax, or statutory purposes.

## Proposed operational rules

1. **Stock reservation:** Reserve available stock when an order is confirmed. Available stock is on-hand quantity less active reservations. Confirmation must reject an order that would exceed available stock.
2. **Sales recognition:** Count an order as an operational sale only when the full order is delivered. Do not treat this operational metric as accounting or tax revenue recognition.
3. **Payments:** Store each received payment as a separate record linked to its order. A payment is recorded only after receipt is confirmed; an order or COD designation alone is not proof of collection.
4. **Pre-delivery cancellation:** On cancellation before delivery, release the order's active reservation exactly once. Do not create a sale for the cancelled order.
5. **Returns:** Require owner approval within a configurable policy window. The window duration and policy details remain to be decided.
6. **Restocking:** Inspect returned goods before restocking. Add accepted, saleable quantities back to available stock; do not restock rejected or uninspected goods.
7. **Partial refunds:** Record every refund separately and cap total refunds for an order at the amount actually collected for that order. A refund does not by itself restock goods.
8. **COGS adjustment:** Retain each order item's original cost snapshot. For accepted returned quantities that are restocked, adjust operational COGS using that original snapshot. Accounting presentation requires professional confirmation.
9. **Transactions and retries:** Order confirmation, reservation, delivery, cancellation, return, restock, and payment/refund writes must be atomic and idempotent. A retry must not duplicate a record or apply an inventory change twice.
10. **Tenant isolation:** Use Supabase row-level security and least-privilege grants for business data. Enforce business membership on the server/database, not solely in the UI; keep privileged keys server-side.

## Unresolved decisions

- Set the return-policy window duration and define eligible items, evidence, and any exceptions.
- Decide whether partial deliveries are supported. If supported, define when the whole order becomes delivered and how undelivered quantities remain reserved.
- Define the owner-approval and inspection workflow, including whether staff roles can approve later.
- Decide how to handle refunds without a return, payment reversals, failed refunds, and multiple payment methods.
- Confirm whether returned goods that are not saleable have a separate inventory disposition.
- Confirm operational COGS and reporting presentation with an accountant; decide whether the MVP needs tax, shipping, or other charges in its reports.
- Define reservation expiry, release on abandoned/unpaid orders, and the business rules for order edits after confirmation.

## Acceptance tests

- Confirming an order reserves its quantities once; a second order cannot reserve more than the remaining available stock.
- A concurrent confirmation race cannot oversell stock. An insufficient-stock failure leaves no partial order or reservation.
- Repeating confirmation or pre-delivery cancellation requests has one effect; cancellation releases only that order's reservation and creates no sale.
- An order counts as an operational sale only after all ordered quantities are marked delivered; partial delivery behavior follows the approved rule.
- An order or COD label without a confirmed receipt creates no payment record. Multiple received payments remain separate and correctly total.
- A return cannot proceed without owner approval within the configured window. Uninspected or rejected goods do not increase available stock.
- Each refund is separately recorded; cumulative refunds cannot exceed confirmed collected payments. Refunds do not change stock without an accepted return/restock event.
- COGS adjustments for restocked returned quantities use the original item cost snapshot; unrelated product cost edits do not change historical order costs.
- Injected failures roll back all related writes. Replaying the same idempotency key does not duplicate orders, reservations, payments, refunds, or stock movements.
- Automated Supabase tests allow authorized access within a business and deny unauthenticated or cross-business reads and writes, including storage access.
