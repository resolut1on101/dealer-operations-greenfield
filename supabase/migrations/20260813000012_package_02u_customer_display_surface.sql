-- Package 02U: user-facing customer display cleanup and authoritative person labels.
-- Raw source values remain unchanged in the base/provenance tables.

create or replace function public.customer_business_compare_key(p_value text)
returns text
language sql
immutable
strict
set search_path = pg_catalog, public
as $$
  select regexp_replace(
    lower(translate(
      regexp_replace(btrim(p_value), '\s+', ' ', 'g'),
      'ÇĞİIÖŞÜçğıöşüÂÎÛâîû',
      'CGIIOSUcgiosuAIUaiu'
    )),
    '[^a-z0-9]+',
    '',
    'g'
  );
$$;

create or replace function public.customer_business_display_name(p_name text)
returns text
language plpgsql
immutable
strict
set search_path = pg_catalog, public
as $$
declare
  v_clean text := regexp_replace(btrim(p_name), '\s+', ' ', 'g');
  v_words text[];
  v_left text;
  v_right text;
  v_index integer;
begin
  if v_clean = '' then
    return v_clean;
  end if;

  v_words := string_to_array(v_clean, ' ');
  if coalesce(array_length(v_words, 1), 0) < 2 then
    return v_clean;
  end if;

  for v_index in 1..array_length(v_words, 1) - 1 loop
    v_left := array_to_string(v_words[1:v_index], ' ');
    v_right := array_to_string(v_words[v_index + 1:array_length(v_words, 1)], ' ');
    if public.customer_business_compare_key(v_left) = public.customer_business_compare_key(v_right) then
      return v_right;
    end if;
  end loop;

  return v_clean;
end;
$$;

revoke all on function public.customer_business_compare_key(text) from public, anon, authenticated;
revoke all on function public.customer_business_display_name(text) from public, anon, authenticated;

create or replace function public.read_current_customer_business_surface()
returns table (
  customer_id text,
  customer_name text,
  trade_name text,
  status public.customer_status,
  channel public.customer_channel,
  segment text,
  representative text,
  chief text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    c.customer_id,
    public.customer_business_display_name(c.customer_name),
    c.trade_name,
    c.status,
    c.channel,
    c.segment,
    case
      when cr.representative_resolution_state = 'RESOLVED' then coalesce(
        (
          select nullif(btrim(raw_name), '')
          from jsonb_array_elements_text(representative.raw_names) as raw(raw_name)
          where nullif(btrim(raw_name), '') is not null
          order by raw_name collate "C"
          limit 1
        ),
        representative.normalized_name
      )
      else null
    end as representative,
    case
      when c.ssm_resolution_state = 'RESOLVED' then c.canonical_ssm
      else null
    end as chief
  from public.customers c
  left join public.customer_resolutions cr
    on cr.customer_id = c.customer_id
   and cr.snapshot_id = c.active_snapshot_id
  left join public.customer_representatives representative
    on representative.id = cr.representative_id
  where c.current_snapshot_state = 'PRESENT_IN_CURRENT_MASTER';
$$;

revoke all on function public.read_current_customer_business_surface() from public;
grant execute on function public.read_current_customer_business_surface() to authenticated;
