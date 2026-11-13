-- OPTIONAL: run AFTER schema.sql and after enabling pg_cron in Database > Extensions.
-- Re-running this script replaces the named job instead of creating duplicates.
select cron.unschedule(jobid)
from cron.job
where jobname = 'purge-deleted-classes';

select cron.schedule(
  'purge-deleted-classes',
  '0 3 * * *',
  $$select public.purge_deleted_classes()$$
);
