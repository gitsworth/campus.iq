-- =====================================================================
-- CampusIQ v2 - full database schema
-- Supabase Dashboard > SQL Editor > New query > paste ALL of this > Run
--
-- IMPORTANT: fresh Supabase project setup only.
-- This script drops/recreates CampusIQ application tables. Do not run it
-- against a project containing data you want to preserve. Use future migrations
-- for updates; never rerun this full schema on a live installation.
-- =====================================================================

-- ---------- 0. Remove old version ----------
drop table if exists notes cascade;
drop table if exists announcements cascade;
drop table if exists calendar_events cascade;
drop table if exists timetable_entries cascade;
drop table if exists time_slots cascade;
drop table if exists class_members cascade;
drop table if exists slot_overrides cascade;
drop table if exists day_overrides cascade;
drop table if exists exam_papers cascade;
drop table if exists subjects cascade;
drop table if exists class_students cascade;
drop table if exists class_teachers cascade;
drop table if exists class_codes cascade;
drop table if exists classes cascade;
drop table if exists profiles cascade;

-- ---------- 1. Profiles ----------
create table profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text not null default 'User',
  created_at timestamptz not null default now()
);

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, full_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'full_name',''), nullif(split_part(coalesce(new.email,''),'@',1),''), 'User'))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- accounts that already exist
insert into profiles (id, full_name)
select id, coalesce(nullif(raw_user_meta_data->>'full_name',''), nullif(split_part(coalesce(email,''),'@',1),''), 'User')
from auth.users on conflict (id) do nothing;

-- ---------- 2. Classes and membership ----------
create table classes (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (length(trim(name)) > 0),
  student_code text not null unique,
  creator_id   uuid not null references auth.users(id) on delete restrict,
  delete_after timestamptz,                 -- set = class is scheduled for deletion
  created_at   timestamptz not null default now()
);

-- teacher code lives separately from the class row; RLS below exposes it to all members
create table class_codes (
  class_id     uuid primary key references classes(id) on delete cascade,
  teacher_code text not null unique
);

create table class_teachers (
  class_id  uuid not null references classes(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (class_id, user_id)
);

create table class_students (
  class_id  uuid not null references classes(id) on delete cascade,
  user_id   uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (class_id, user_id),
  unique (user_id)                          -- a student can be in only ONE class
);

-- ---------- 3. Helper functions (used by security policies) ----------
create or replace function is_teacher(cid uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from class_teachers t join classes c on c.id = t.class_id
    where t.class_id = cid and t.user_id = auth.uid()
      and (c.delete_after is null or c.delete_after > now()))
$$;

create or replace function is_student(cid uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from class_students s join classes c on c.id = s.class_id
    where s.class_id = cid and s.user_id = auth.uid()
      and (c.delete_after is null or c.delete_after > now()))
$$;

create or replace function is_member(cid uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select is_teacher(cid) or is_student(cid)
$$;

-- ---------- 4. Limits: 100 students per class, 100 classes per teacher ----------
create or replace function enforce_student_rules() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Serialize joins to the same class so concurrent requests cannot exceed 100.
  perform pg_advisory_xact_lock(hashtextextended(new.class_id::text, 0));
  if (select count(*) from class_students where class_id = new.class_id) >= 100 then
    raise exception 'This class is full (100 students maximum).';
  end if;
  if exists (select 1 from class_teachers where class_id = new.class_id and user_id = new.user_id) then
    raise exception 'You are already a teacher in this class.';
  end if;
  return new;
end $$;
create trigger trg_student_rules before insert on class_students
  for each row execute function enforce_student_rules();

create or replace function enforce_teacher_rules() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Serialize class joins for this user so the 100-class limit is reliable.
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 1));
  if (select count(*) from class_teachers where user_id = new.user_id) >= 100 then
    raise exception 'You can teach in at most 100 classes.';
  end if;
  if exists (select 1 from class_students where class_id = new.class_id and user_id = new.user_id) then
    raise exception 'You are already a student in this class.';
  end if;
  return new;
end $$;
create trigger trg_teacher_rules before insert on class_teachers
  for each row execute function enforce_teacher_rules();

-- ---------- 5. Class functions the app calls ----------
create or replace function gen_code(prefix text) returns text
language sql volatile as $$
  select prefix || string_agg(
    substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (floor(random()*32)+1)::int, 1), '')
  from generate_series(1, 6)
$$;

create or replace function create_class(p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid; scode text; tcode text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if length(trim(p_name)) = 0 then raise exception 'Class name is required'; end if;
  loop
    scode := gen_code('S');
    exit when not exists (select 1 from classes where student_code = scode);
  end loop;
  loop
    tcode := gen_code('T');
    exit when not exists (select 1 from class_codes where teacher_code = tcode);
  end loop;
  insert into classes (name, student_code, creator_id)
    values (trim(p_name), scode, auth.uid()) returning id into cid;
  insert into class_codes (class_id, teacher_code) values (cid, tcode);
  insert into class_teachers (class_id, user_id) values (cid, auth.uid());
  return cid;
end $$;

create or replace function join_as_teacher(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select cc.class_id into cid from class_codes cc join classes c on c.id = cc.class_id
   where cc.teacher_code = upper(trim(p_code))
     and (c.delete_after is null or c.delete_after > now());
  if cid is null then raise exception 'Invalid teacher code'; end if;
  if exists (select 1 from class_teachers where class_id = cid and user_id = auth.uid()) then
    raise exception 'You are already a teacher in this class.';
  end if;
  insert into class_teachers (class_id, user_id) values (cid, auth.uid());
  return cid;
end $$;

create or replace function join_as_student(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select id into cid from classes
   where student_code = upper(trim(p_code))
     and (delete_after is null or delete_after > now());
  if cid is null then raise exception 'Invalid student code'; end if;
  if exists (select 1 from class_students where user_id = auth.uid()) then
    raise exception 'You are already in a class. Leave it first to join another.';
  end if;
  insert into class_students (class_id, user_id) values (cid, auth.uid());
  return cid;
end $$;

-- creator only: delete happens 30 days later, can be undone until then
create or replace function schedule_class_delete(p_class uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update classes set delete_after = now() + interval '30 days'
   where id = p_class and creator_id = auth.uid() and delete_after is null;
  if not found then raise exception 'Only the creator can delete this class'; end if;
end $$;

create or replace function cancel_class_delete(p_class uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update classes set delete_after = null
   where id = p_class and creator_id = auth.uid()
     and delete_after is not null and delete_after > now();
  if not found then raise exception 'Only the creator can do this'; end if;
end $$;

-- the creator must still see the class during the 30 days to be able to undo
create or replace function creator_can_see(cid uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from classes where id = cid and creator_id = auth.uid())
$$;

-- permanent clean-up (see supabase/step2_cron.sql)
create or replace function purge_deleted_classes() returns void
language sql security definer set search_path = public as $$
  delete from classes where delete_after is not null and delete_after < now();
$$;

-- ---------- 6. Class content ----------
create table subjects (
  id         uuid primary key default gen_random_uuid(),
  class_id   uuid not null references classes(id) on delete cascade,
  name       text not null check (length(trim(name)) > 0),
  code       text,
  teacher_id uuid references auth.users(id) on delete set null,
  color      text not null default '#3D4BDB',
  created_at timestamptz not null default now()
);

create table time_slots (
  id         uuid primary key default gen_random_uuid(),
  class_id   uuid not null references classes(id) on delete cascade,
  start_time time not null,
  end_time   time not null check (end_time > start_time),
  label      text,
  is_break   boolean not null default false
);

create table timetable_entries (
  id         uuid primary key default gen_random_uuid(),
  class_id   uuid not null references classes(id) on delete cascade,
  weekday    int  not null check (weekday between 1 and 7),   -- 1 = Monday
  slot_id    uuid not null references time_slots(id) on delete cascade,
  subject_id uuid not null references subjects(id) on delete cascade,
  room       text,
  unique (class_id, weekday, slot_id)
);

-- one date follows another weekday's timetable (temporary)
create table day_overrides (
  id             uuid primary key default gen_random_uuid(),
  class_id       uuid not null references classes(id) on delete cascade,
  on_date        date not null,
  follow_weekday int check (follow_weekday between 1 and 7),
  note           text,
  unique (class_id, on_date)
);

-- one period on one date is changed or cancelled (temporary)
create table slot_overrides (
  id         uuid primary key default gen_random_uuid(),
  class_id   uuid not null references classes(id) on delete cascade,
  on_date    date not null,
  slot_id    uuid not null references time_slots(id) on delete cascade,
  subject_id uuid references subjects(id) on delete set null,
  room       text,
  cancelled  boolean not null default false,
  note       text,
  unique (class_id, on_date, slot_id)
);

create table calendar_events (
  id          uuid primary key default gen_random_uuid(),
  class_id    uuid not null references classes(id) on delete cascade,
  subject_id  uuid references subjects(id) on delete set null,
  title       text not null,
  description text,
  event_date  date not null,
  event_type  text not null check (event_type in ('holiday','deadline')),
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table exam_papers (
  id         uuid primary key default gen_random_uuid(),
  class_id   uuid not null references classes(id) on delete cascade,
  exam_name  text not null,
  subject_id uuid not null references subjects(id) on delete cascade,
  exam_date  date not null,
  start_time time not null,
  end_time   time not null check (end_time > start_time),
  room       text,
  created_by uuid references auth.users(id) on delete set null
);

create table announcements (
  id          uuid primary key default gen_random_uuid(),
  class_id    uuid not null references classes(id) on delete cascade,
  subject_id  uuid references subjects(id) on delete cascade,   -- null = class-wide
  title       text not null,
  body        text,
  attachments jsonb not null default '[]'::jsonb,
  is_auto     boolean not null default false,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table notes (
  id          uuid primary key default gen_random_uuid(),
  class_id    uuid not null references classes(id) on delete cascade,
  subject_id  uuid not null references subjects(id) on delete cascade,
  title       text not null,
  file_path   text not null,
  file_name   text not null,
  file_size   bigint,
  version_group_id uuid not null default gen_random_uuid(),
  version_number integer not null default 1 check (version_number > 0),
  supersedes_id uuid references notes(id) on delete set null,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create unique index subjects_class_name_unique on subjects (class_id, lower(trim(name)));

create or replace function validate_subject_teacher_membership() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.teacher_id is not null and not exists (
    select 1 from class_teachers t
     where t.class_id = new.class_id and t.user_id = new.teacher_id
  ) then
    raise exception 'The assigned subject teacher must be a current teacher in this class.';
  end if;
  return new;
end $$;
create trigger trg_validate_subject_teacher
before insert or update of class_id, teacher_id on subjects
for each row execute function validate_subject_teacher_membership();
create index on subjects (class_id);
create index on timetable_entries (class_id);
create index on calendar_events (class_id, event_date);
create index on announcements (class_id, created_at desc);
create index on notes (class_id, created_at desc);
create index on notes (version_group_id, version_number desc);

-- ---------- 7. Row Level Security ----------
alter table profiles          enable row level security;
alter table classes           enable row level security;
alter table class_codes       enable row level security;
alter table class_teachers    enable row level security;
alter table class_students    enable row level security;
alter table subjects          enable row level security;
alter table time_slots        enable row level security;
alter table timetable_entries enable row level security;
alter table day_overrides     enable row level security;
alter table slot_overrides    enable row level security;
alter table calendar_events   enable row level security;
alter table exam_papers       enable row level security;
alter table announcements     enable row level security;
alter table notes             enable row level security;

create policy "profiles read"   on profiles for select to authenticated using (true);
create policy "profiles update" on profiles for update to authenticated using (id = auth.uid());

create policy "classes read" on classes for select to authenticated
  using (is_member(id) or creator_can_see(id));

-- Both codes are visible to every current class member, as specified.
create policy "codes read" on class_codes for select to authenticated
  using (is_member(class_id));

create policy "teachers read"  on class_teachers for select to authenticated using (is_member(class_id));
-- A creator must transfer ownership before leaving the class.
create policy "teacher leave" on class_teachers for delete to authenticated
  using (user_id = auth.uid() and exists (
    select 1 from classes c where c.id = class_teachers.class_id
      and c.creator_id <> auth.uid()
  ));
create policy "students read"  on class_students for select to authenticated using (is_member(class_id));
create policy "student leave" on class_students for delete to authenticated
  using (user_id = auth.uid());
create policy "creator remove student" on class_students for delete to authenticated
  using (exists (select 1 from classes c
    where c.id = class_students.class_id and c.creator_id = auth.uid()));

create policy "subjects read"   on subjects for select to authenticated using (is_member(class_id));
create policy "subjects add"    on subjects for insert to authenticated
  with check (is_teacher(class_id) and teacher_id = auth.uid());
-- Current assigned teachers can manage their own subjects. The class creator
-- can always manage/reassign any subject, including subjects of departed teachers.
create policy "subjects edit" on subjects for update to authenticated
  using (is_teacher(class_id) and (
    teacher_id = auth.uid() or exists (
      select 1 from classes c where c.id = subjects.class_id and c.creator_id = auth.uid()
    )))
  with check (is_teacher(class_id));
create policy "subjects delete" on subjects for delete to authenticated
  using (is_teacher(class_id) and (
    teacher_id = auth.uid() or exists (
      select 1 from classes c where c.id = subjects.class_id and c.creator_id = auth.uid()
    )));

-- shared class data: everyone in the class reads, any teacher of the class writes
create policy "slots read"  on time_slots for select to authenticated using (is_member(class_id));
create policy "slots write" on time_slots for all to authenticated using (is_teacher(class_id)) with check (is_teacher(class_id));

create policy "tt read"  on timetable_entries for select to authenticated using (is_member(class_id));
create policy "tt write" on timetable_entries for all to authenticated using (is_teacher(class_id)) with check (is_teacher(class_id));

create policy "dayov read"  on day_overrides for select to authenticated using (is_member(class_id));
create policy "dayov write" on day_overrides for all to authenticated using (is_teacher(class_id)) with check (is_teacher(class_id));

create policy "slotov read"  on slot_overrides for select to authenticated using (is_member(class_id));
create policy "slotov write" on slot_overrides for all to authenticated using (is_teacher(class_id)) with check (is_teacher(class_id));

create policy "events read"  on calendar_events for select to authenticated using (is_member(class_id));
create policy "events write" on calendar_events for all to authenticated using (is_teacher(class_id)) with check (is_teacher(class_id));

create policy "exams read"  on exam_papers for select to authenticated using (is_member(class_id));
create policy "exams write" on exam_papers for all to authenticated using (is_teacher(class_id)) with check (is_teacher(class_id));

create policy "ann read" on announcements for select to authenticated using (is_member(class_id));
create policy "ann add"  on announcements for insert to authenticated
  with check (
    is_teacher(class_id) and created_by = auth.uid()
    and (subject_id is null or exists (
      select 1 from subjects s where s.id = subject_id and s.class_id = announcements.class_id
        and (s.teacher_id = auth.uid() or exists (
          select 1 from classes c where c.id = s.class_id and c.creator_id = auth.uid()
        ))))
  );
create policy "ann delete" on announcements for delete to authenticated
  using (created_by = auth.uid() and is_teacher(class_id));
create policy "creator delete announcements" on announcements for delete to authenticated
  using (exists (select 1 from classes c
    where c.id = announcements.class_id and c.creator_id = auth.uid()));

-- Security-definer helper avoids recursive RLS when checking version history.
create or replace function note_is_latest(p_group uuid, p_version integer)
returns boolean
language sql security definer stable set search_path = public as $$
  select p_version = max(version_number)
    from notes where version_group_id = p_group
$$;
revoke all on function note_is_latest(uuid, integer) from public;
grant execute on function note_is_latest(uuid, integer) to authenticated;

-- Teachers can inspect full note history; students see only the latest version.
create policy "notes read" on notes for select to authenticated
  using (is_member(class_id) and (
    is_teacher(class_id) or note_is_latest(version_group_id, version_number)
  ));
create policy "notes add"  on notes for insert to authenticated
  with check (
    is_teacher(class_id) and uploaded_by = auth.uid()
    and exists (select 1 from subjects s where s.id = subject_id
      and s.class_id = notes.class_id
      and (s.teacher_id = auth.uid() or exists (
        select 1 from classes c where c.id = s.class_id and c.creator_id = auth.uid()
      )))
  );
create policy "notes delete" on notes for delete to authenticated
  using (is_teacher(class_id) and (
    uploaded_by = auth.uid() or exists (
      select 1 from classes c where c.id = notes.class_id and c.creator_id = auth.uid()
    )));

-- ---------- 8. File storage (notes + attachments) ----------
insert into storage.buckets (id, name, public)
values ('class-files', 'class-files', false)
on conflict (id) do nothing;

drop policy if exists "class files read"   on storage.objects;
drop policy if exists "class files upload" on storage.objects;
drop policy if exists "class files delete" on storage.objects;

create policy "class files read" on storage.objects for select to authenticated
  using (bucket_id = 'class-files' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "class files upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'class-files' and public.is_teacher(((storage.foldername(name))[1])::uuid));
create policy "class files delete" on storage.objects for delete to authenticated
  using (bucket_id = 'class-files' and public.is_teacher(((storage.foldername(name))[1])::uuid));


-- ---------- 9. Ownership transfer ----------
-- The new creator must already be a teacher in the same class.
create or replace function transfer_class_ownership(p_class uuid, p_new_creator uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update classes c
     set creator_id = p_new_creator
   where c.id = p_class
     and c.creator_id = auth.uid()
     and exists (
       select 1 from class_teachers t
        where t.class_id = p_class and t.user_id = p_new_creator
     );
  if not found then
    raise exception 'Only the current creator can transfer ownership to an existing teacher.';
  end if;
end $$;

revoke all on function transfer_class_ownership(uuid, uuid) from public;
grant execute on function transfer_class_ownership(uuid, uuid) to authenticated;

-- Lock down privileged RPC entry points.
revoke all on function create_class(text) from public;
revoke all on function join_as_teacher(text) from public;
revoke all on function join_as_student(text) from public;
revoke all on function schedule_class_delete(uuid) from public;
revoke all on function cancel_class_delete(uuid) from public;
grant execute on function create_class(text) to authenticated;
grant execute on function join_as_teacher(text) to authenticated;
grant execute on function join_as_student(text) to authenticated;
grant execute on function schedule_class_delete(uuid) to authenticated;
grant execute on function cancel_class_delete(uuid) to authenticated;
revoke all on function purge_deleted_classes() from public;
