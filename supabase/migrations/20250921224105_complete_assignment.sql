-- Migration: Complete Assignment
-- This migration adds the ability to mark an assignment as complete, which
-- indicates that the scholar has completed their work and should be compensated.
alter table assignments
add column completed boolean not null default false;

create index idx_assignments_completed on assignments(completed);