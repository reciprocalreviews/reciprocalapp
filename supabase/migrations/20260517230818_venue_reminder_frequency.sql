alter table public.venues
add column transaction_reminder_frequency_days integer not null default 0;

alter table public.venues
add column transaction_reminder_time timestamp with time zone;

alter table public.venues
add constraint venues_transaction_reminder_frequency_days_check
check (transaction_reminder_frequency_days >= 0 and transaction_reminder_frequency_days <= 90);
