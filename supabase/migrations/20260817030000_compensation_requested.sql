-- Record when a scholar requests compensation for an assignment.
--
-- An approved-but-uncompleted assignment is ambiguous: it is usually a review
-- still in progress, but after the reviewer follows the decision email's
-- compensation link it is finished work awaiting an approver. The two were
-- indistinguishable, so the CompensationRequested email was necessarily
-- one-shot — if the approver missed it, nothing ever nagged again, and a
-- recurring reminder over all uncompleted assignments would nag approvers
-- about reviews that simply aren't done yet.
--
-- requestCompensation stamps this column (the scholar updates their own
-- assignment row, which the assignments UPDATE policy already permits), and
-- the daily remind function nags the approver chain only for stamped,
-- uncompleted assignments.

alter table public.assignments
add column compensation_requested_at timestamp with time zone default null;
