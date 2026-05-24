-- Split decline metadata off `transactions.purpose` so the original
-- purpose is preserved when a transaction is declined and the decliner's
-- identity is recorded for audit / follow-up. Also rename the enum value
-- 'canceled' → 'declined' to match user-facing language ("decline" is the
-- active verb the UI now uses everywhere).

alter type public.transaction_status rename value 'canceled' to 'declined';

alter table public.transactions
    add column if not exists decliner uuid references public.scholars(id),
    add column if not exists decline_reason text;
