-- Management policies were originally declared FOR ALL while separate read
-- policies already covered SELECT. PostgreSQL treats FOR ALL as including
-- SELECT, so both permissive policies were evaluated for every read.
--
-- Preserve the existing read policies and split only the overlapping
-- management policies into action-specific write policies. The USING and
-- WITH CHECK expressions are copied from the existing catalog definitions so
-- this migration does not broaden or narrow access.

do $$
declare
  policy_record record;
  overlapping_policy_count integer;
  remaining_overlap_count integer;
begin
  select count(*)
  into overlapping_policy_count
  from pg_policies as management_policy
  where management_policy.schemaname = 'public'
    and management_policy.permissive = 'PERMISSIVE'
    and management_policy.cmd = 'ALL'
    and exists (
      select 1
      from pg_policies as read_policy
      where read_policy.schemaname = management_policy.schemaname
        and read_policy.tablename = management_policy.tablename
        and read_policy.roles = management_policy.roles
        and read_policy.permissive = management_policy.permissive
        and read_policy.cmd = 'SELECT'
    );

  if overlapping_policy_count <> 30 then
    raise exception
      'Expected 30 overlapping management policies, found %',
      overlapping_policy_count;
  end if;

  for policy_record in
    select
      management_policy.schemaname,
      management_policy.tablename,
      management_policy.policyname,
      coalesce(management_policy.qual, 'true') as using_expression,
      coalesce(
        management_policy.with_check,
        management_policy.qual,
        'true'
      ) as check_expression,
      (
        select string_agg(format('%I', role_name), ', ')
        from unnest(management_policy.roles) as role_name
      ) as role_list
    from pg_policies as management_policy
    where management_policy.schemaname = 'public'
      and management_policy.permissive = 'PERMISSIVE'
      and management_policy.cmd = 'ALL'
      and exists (
        select 1
        from pg_policies as read_policy
        where read_policy.schemaname = management_policy.schemaname
          and read_policy.tablename = management_policy.tablename
          and read_policy.roles = management_policy.roles
          and read_policy.permissive = management_policy.permissive
          and read_policy.cmd = 'SELECT'
      )
    order by management_policy.tablename, management_policy.policyname
  loop
    execute format(
      'drop policy %I on %I.%I',
      policy_record.policyname,
      policy_record.schemaname,
      policy_record.tablename
    );

    execute format(
      'create policy %I on %I.%I as permissive for insert to %s with check (%s)',
      policy_record.policyname || ' insert',
      policy_record.schemaname,
      policy_record.tablename,
      policy_record.role_list,
      policy_record.check_expression
    );

    execute format(
      'create policy %I on %I.%I as permissive for update to %s using (%s) with check (%s)',
      policy_record.policyname || ' update',
      policy_record.schemaname,
      policy_record.tablename,
      policy_record.role_list,
      policy_record.using_expression,
      policy_record.check_expression
    );

    execute format(
      'create policy %I on %I.%I as permissive for delete to %s using (%s)',
      policy_record.policyname || ' delete',
      policy_record.schemaname,
      policy_record.tablename,
      policy_record.role_list,
      policy_record.using_expression
    );
  end loop;

  select count(*)
  into remaining_overlap_count
  from pg_policies as management_policy
  where management_policy.schemaname = 'public'
    and management_policy.permissive = 'PERMISSIVE'
    and management_policy.cmd = 'ALL'
    and exists (
      select 1
      from pg_policies as read_policy
      where read_policy.schemaname = management_policy.schemaname
        and read_policy.tablename = management_policy.tablename
        and read_policy.roles = management_policy.roles
        and read_policy.permissive = management_policy.permissive
        and read_policy.cmd = 'SELECT'
    );

  if remaining_overlap_count <> 0 then
    raise exception
      'Overlapping management policies remain after split: %',
      remaining_overlap_count;
  end if;
end;
$$;
