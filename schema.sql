-- Scholarship Monitoring System: schema, RLS, functions, seed data.
-- BEFORE running: create 2 users in Supabase Auth > Users (Auto Confirm ON):
--   staff@test.local and scholar@test.local (choose your own passwords).
-- Then paste this whole file in Supabase > SQL Editor > Run.

create table programs (
  program_id serial primary key,
  name text unique not null,
  max_gwa numeric(3,2) not null, min_units int not null,
  max_failed int not null, max_incomplete int not null, max_dropped int not null,
  deadline timestamptz not null
);
create table profiles (
  user_id uuid primary key,
  student_no text unique, full_name text not null, email text,
  role text not null check (role in ('scholar','staff'))
);
create table scholar_assignments (
  assignment_id serial primary key,
  scholar_id uuid unique not null references profiles(user_id),
  program_id int not null references programs(program_id),
  assigned_by uuid references profiles(user_id),
  assigned_at timestamptz default now()
);
create table submissions (
  submission_id bigserial primary key,
  scholar_id uuid not null references profiles(user_id),
  academic_year text not null,
  semester int not null check (semester in (1,2)),
  gwa numeric(3,2) not null check (gwa between 1 and 5),
  enrolled_units int not null check (enrolled_units >= 0),
  failed_count int not null check (failed_count >= 0),
  incomplete_count int not null check (incomplete_count >= 0),
  dropped_count int not null check (dropped_count >= 0),
  evidence_ref text not null check (btrim(evidence_ref) <> ''),
  submitted_at timestamptz not null default now(),
  verification_status text not null default 'Pending verification'
    check (verification_status in ('Pending verification','Verified','Returned')),
  verification_reason text,
  verified_by uuid references profiles(user_id),
  compliance_result text not null default 'Not evaluated'
    check (compliance_result in ('Not evaluated','Compliant','With Deficiency')),
  evaluation jsonb,
  renewal_decision text not null default 'No decision yet'
    check (renewal_decision in ('No decision yet','Approved','Held')),
  decision_note text,
  unique (scholar_id, academic_year, semester)
);
create table decision_history (
  history_id bigserial primary key,
  submission_id bigint not null references submissions(submission_id),
  actor_id uuid not null,
  action_type text not null, old_value text, new_value text, note text,
  created_at timestamptz not null default now()
);

-- ===== Row Level Security =====
alter table programs enable row level security;
alter table profiles enable row level security;
alter table scholar_assignments enable row level security;
alter table submissions enable row level security;
alter table decision_history enable row level security;

create function is_staff() returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where user_id = auth.uid() and role = 'staff') $$;

create policy prog_read on programs for select to authenticated using (true);
create policy prof_read on profiles for select to authenticated using (user_id = auth.uid() or is_staff());
create policy asg_read on scholar_assignments for select to authenticated using (scholar_id = auth.uid() or is_staff());
create policy sub_read on submissions for select to authenticated using (scholar_id = auth.uid() or is_staff());
create policy hist_read on decision_history for select to authenticated using (is_staff());
-- No insert/update/delete policies: all writes go through the functions below.
revoke insert, update, delete on all tables in schema public from anon, authenticated;
revoke all on all tables in schema public from anon;

-- ===== Functions (checked inside the database) =====
create function check_input(p_year text, p_sem numeric, p_gwa numeric, p_units numeric,
  p_f numeric, p_i numeric, p_d numeric, p_ref text) returns void language plpgsql as $$
begin
  if p_year is null or p_sem is null or p_gwa is null or p_units is null or p_f is null or p_i is null or p_d is null then
    raise exception 'Please fill in all fields.'; end if;
  if p_gwa < 1 or p_gwa > 5 then raise exception 'GWA must be from 1.00 to 5.00.'; end if;
  if p_units < 0 or p_f < 0 or p_i < 0 or p_d < 0
     or p_units <> trunc(p_units) or p_f <> trunc(p_f) or p_i <> trunc(p_i) or p_d <> trunc(p_d) then
    raise exception 'Units and counts must be whole numbers, zero or higher.'; end if;
  if p_sem not in (1,2) then raise exception 'Semester must be 1 or 2.'; end if;
  if p_ref is null or btrim(p_ref) = '' then raise exception 'Grade-document reference is required.'; end if;
end $$;

create function submit_grades(p_year text, p_sem numeric, p_gwa numeric, p_units numeric,
  p_failed numeric, p_inc numeric, p_drop numeric, p_ref text) returns bigint
language plpgsql security definer set search_path=public as $$
declare new_id bigint;
begin
  if not exists (select 1 from profiles where user_id = auth.uid() and role = 'scholar') then
    raise exception 'Only scholars can submit grades.'; end if;
  if not exists (select 1 from scholar_assignments where scholar_id = auth.uid()) then
    raise exception 'You are not assigned to a program yet.'; end if;
  perform check_input(p_year, p_sem, p_gwa, p_units, p_failed, p_inc, p_drop, p_ref);
  if exists (select 1 from submissions where scholar_id = auth.uid() and academic_year = p_year and semester = p_sem::int) then
    raise exception 'This semester was already submitted.'; end if;
  insert into submissions(scholar_id, academic_year, semester, gwa, enrolled_units, failed_count, incomplete_count, dropped_count, evidence_ref)
  values (auth.uid(), p_year, p_sem::int, p_gwa, p_units::int, p_failed::int, p_inc::int, p_drop::int, btrim(p_ref))
  returning submission_id into new_id;
  insert into decision_history(submission_id, actor_id, action_type, new_value) values (new_id, auth.uid(), 'Submit', 'Pending verification');
  return new_id;
end $$;

create function resubmit_grades(p_id bigint, p_year text, p_sem numeric, p_gwa numeric, p_units numeric,
  p_failed numeric, p_inc numeric, p_drop numeric, p_ref text) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not exists (select 1 from submissions where submission_id = p_id and scholar_id = auth.uid() and verification_status = 'Returned') then
    raise exception 'Only your own Returned submissions can be corrected.'; end if;
  perform check_input(p_year, p_sem, p_gwa, p_units, p_failed, p_inc, p_drop, p_ref);
  if exists (select 1 from submissions where scholar_id = auth.uid() and academic_year = p_year and semester = p_sem::int and submission_id <> p_id) then
    raise exception 'This semester was already submitted.'; end if;
  update submissions set academic_year = p_year, semester = p_sem::int, gwa = p_gwa, enrolled_units = p_units::int,
    failed_count = p_failed::int, incomplete_count = p_inc::int, dropped_count = p_drop::int, evidence_ref = btrim(p_ref),
    verification_status = 'Pending verification', compliance_result = 'Not evaluated', evaluation = null,
    renewal_decision = 'No decision yet', decision_note = null
  where submission_id = p_id;
  insert into decision_history(submission_id, actor_id, action_type, old_value, new_value)
  values (p_id, auth.uid(), 'Resubmit', 'Returned', 'Pending verification');
end $$;

create function verify_submission(p_id bigint, p_status text, p_reason text) returns void
language plpgsql security definer set search_path=public as $$
declare old text;
begin
  if not is_staff() then raise exception 'Staff only.'; end if;
  if p_status not in ('Verified','Returned') then raise exception 'Status must be Verified or Returned.'; end if;
  if p_status = 'Returned' and btrim(coalesce(p_reason,'')) = '' then
    raise exception 'A reason is required when returning evidence.'; end if;
  select verification_status into old from submissions where submission_id = p_id;
  if old is null then raise exception 'Submission not found.'; end if;
  if old <> 'Pending verification' then raise exception 'Only Pending verification records can be verified or returned.'; end if;
  update submissions set verification_status = p_status,
    verification_reason = case when p_status = 'Returned' then p_reason else null end, verified_by = auth.uid()
  where submission_id = p_id;
  insert into decision_history(submission_id, actor_id, action_type, old_value, new_value, note)
  values (p_id, auth.uid(), 'Verify', old, p_status, p_reason);
end $$;

create function mk(n text, ok boolean, pass_txt text, fail_txt text) returns jsonb language sql immutable as
$$ select jsonb_build_object('check', n, 'ok', ok, 'detail', case when ok then pass_txt else fail_txt end) $$;

create function evaluate_submission(p_id bigint) returns void
language plpgsql security definer set search_path=public as $$
declare s submissions; pr programs; chk jsonb; res text; why text;
begin
  if not is_staff() then raise exception 'Staff only.'; end if;
  select * into s from submissions where submission_id = p_id;
  if not found then raise exception 'Submission not found.'; end if;
  if s.verification_status <> 'Verified' then raise exception 'Evidence must be verified first.'; end if;
  if btrim(coalesce(s.evidence_ref,'')) = '' then raise exception 'Evidence reference is missing.'; end if;
  select g.* into pr from programs g join scholar_assignments a on a.program_id = g.program_id where a.scholar_id = s.scholar_id;
  if not found then raise exception 'No program record found for this scholar.'; end if;
  chk := jsonb_build_array(
    mk('GWA', s.gwa <= pr.max_gwa, format('GWA %s is within the maximum of %s', s.gwa, pr.max_gwa), format('GWA %s is above the maximum of %s', s.gwa, pr.max_gwa)),
    mk('Enrolled units', s.enrolled_units >= pr.min_units, format('%s units meets the minimum of %s', s.enrolled_units, pr.min_units), format('Insufficient units: %s, minimum is %s', s.enrolled_units, pr.min_units)),
    mk('Failed subjects', s.failed_count <= pr.max_failed, format('%s failed, allowed %s', s.failed_count, pr.max_failed), format('Failing subject: %s failed, allowed %s', s.failed_count, pr.max_failed)),
    mk('Incomplete grades', s.incomplete_count <= pr.max_incomplete, format('%s incomplete, allowed %s', s.incomplete_count, pr.max_incomplete), format('Incomplete grade: %s incomplete, allowed %s', s.incomplete_count, pr.max_incomplete)),
    mk('Dropped subjects', s.dropped_count <= pr.max_dropped, format('%s dropped, allowed %s', s.dropped_count, pr.max_dropped), format('Too many dropped subjects: %s, allowed %s', s.dropped_count, pr.max_dropped)),
    mk('Deadline', s.submitted_at <= pr.deadline, 'Submitted on time', 'Late submission')
  );
  select string_agg(e->>'detail', '; ') into why from jsonb_array_elements(chk) e where not (e->>'ok')::boolean;
  res := case when why is null then 'Compliant' else 'With Deficiency' end;
  update submissions set compliance_result = res, evaluation = chk where submission_id = p_id;
  insert into decision_history(submission_id, actor_id, action_type, old_value, new_value, note)
  values (p_id, auth.uid(), 'Evaluate', s.compliance_result, res, why);
end $$;

create function decide_renewal(p_id bigint, p_decision text, p_note text) returns void
language plpgsql security definer set search_path=public as $$
declare s submissions;
begin
  if not is_staff() then raise exception 'Staff only.'; end if;
  if p_decision not in ('Approved','Held') then raise exception 'Decision must be Approved or Held.'; end if;
  select * into s from submissions where submission_id = p_id;
  if not found then raise exception 'Submission not found.'; end if;
  if p_decision = 'Approved' and (s.verification_status <> 'Verified' or s.compliance_result <> 'Compliant') then
    raise exception 'Approval requires verified evidence and a Compliant evaluation.'; end if;
  update submissions set renewal_decision = p_decision, decision_note = p_note where submission_id = p_id;
  insert into decision_history(submission_id, actor_id, action_type, old_value, new_value, note)
  values (p_id, auth.uid(), 'Renewal', s.renewal_decision, p_decision, p_note);
end $$;

create function register_scholar(p_student_no text, p_name text, p_email text, p_program int) returns void
language plpgsql security definer set search_path=public as $$
declare uid uuid;
begin
  if not is_staff() then raise exception 'Staff only.'; end if;
  if btrim(coalesce(p_student_no,'')) = '' or btrim(coalesce(p_name,'')) = '' then raise exception 'Student ID and name are required.'; end if;
  if exists (select 1 from profiles where student_no = p_student_no) then raise exception 'Student ID already exists.'; end if;
  select id into uid from auth.users where lower(email) = lower(p_email);
  if uid is null then uid := gen_random_uuid(); end if;  -- no login yet
  insert into profiles(user_id, student_no, full_name, email, role) values (uid, p_student_no, p_name, p_email, 'scholar');
  insert into scholar_assignments(scholar_id, program_id, assigned_by) values (uid, p_program, auth.uid());
end $$;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated;

-- ===== Seed data (synthetic) =====
insert into programs(name, max_gwa, min_units, max_failed, max_incomplete, max_dropped, deadline) values
 ('Merit Scholar', 1.75, 18, 0, 0, 0, '2026-10-30 17:00:00+08'),
 ('Community Scholar', 2.25, 15, 0, 0, 1, '2026-10-30 17:00:00+08');

insert into profiles(user_id, student_no, full_name, email, role) values
 ((select id from auth.users where email = 'staff@test.local'), 'STAFF1', 'Test Staff', 'staff@test.local', 'staff'),
 ((select id from auth.users where email = 'scholar@test.local'), 'A01', 'Ana Cruz', 'scholar@test.local', 'scholar'),
 (gen_random_uuid(), 'A02', 'Ben Santos', 'a02@test.local', 'scholar'),
 (gen_random_uuid(), 'A03', 'Carla Lim', 'a03@test.local', 'scholar'),
 (gen_random_uuid(), 'A04', 'Dino Reyes', 'a04@test.local', 'scholar'),
 (gen_random_uuid(), 'A05', 'Ella Tan', 'a05@test.local', 'scholar'),
 (gen_random_uuid(), 'A06', 'Felix Go', 'a06@test.local', 'scholar');

insert into scholar_assignments(scholar_id, program_id, assigned_by)
select p.user_id, g.program_id, (select user_id from profiles where role = 'staff')
from profiles p
join (values ('A01','Merit Scholar'),('A02','Merit Scholar'),('A03','Community Scholar'),
             ('A04','Community Scholar'),('A05','Merit Scholar'),('A06','Community Scholar')) v(sno, pname) on v.sno = p.student_no
join programs g on g.name = v.pname;

insert into submissions(scholar_id, academic_year, semester, gwa, enrolled_units, failed_count, incomplete_count,
                        dropped_count, evidence_ref, submitted_at, verification_status, verified_by)
select p.user_id, '2026-2027', 1, v.gwa, v.units, v.f, v.i, v.d, 'GRADES-' || v.sno, v.ts::timestamptz, v.vs,
       case when v.vs = 'Verified' then (select user_id from profiles where role = 'staff') end
from profiles p
join (values
 ('A01', 1.75, 18, 0, 0, 0, '2026-10-30 17:00:00+08', 'Verified'),
 ('A02', 1.76, 18, 0, 0, 0, '2026-10-29 12:00:00+08', 'Verified'),
 ('A03', 2.25, 15, 0, 0, 1, '2026-10-29 12:00:00+08', 'Verified'),
 ('A04', 2.25, 14, 0, 1, 0, '2026-10-29 12:00:00+08', 'Verified'),
 ('A05', 1.50, 18, 1, 0, 0, '2026-10-30 17:01:00+08', 'Verified'),
 ('A06', 2.00, 15, 0, 0, 0, '2026-10-29 12:00:00+08', 'Pending verification')
) v(sno, gwa, units, f, i, d, ts, vs) on v.sno = p.student_no;
