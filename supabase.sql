-- 練習ベース：グループ共有の準備（Supabase の SQL Editor に貼って1回実行する）
--
-- しくみ
--   ・表は rb_groups（グループ）と rb_items（共有されたカード・ひな型）の2つ。
--   ・アプリに入っているキーは公開されるので、表には直接さわらせない（RLSを有効にして、許可を1つも出さない）。
--   ・読み書きは、下の関数だけを通す。関数は「グループコード＋合言葉」が合っている時だけ動く。
--   ・グループを作れるのは「作成キー」を知っている人だけ。作成キーはこのファイルの最後で決める。
--   ・何度実行しても同じ結果になる（作りなおしても、入っているデータは消えない）。

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.rb_config(
  key text primary key,
  value text not null
);
create table if not exists public.rb_groups(
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  pass_hash text not null,
  created_at timestamptz not null default now()
);
create table if not exists public.rb_items(
  group_id uuid not null references public.rb_groups(id) on delete cascade,
  id text not null,
  kind text not null check (kind in ('card','plan')),
  owner uuid not null,
  author text not null default '',
  summary jsonb not null default '{}'::jsonb,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (group_id, id)
);

alter table public.rb_config enable row level security;
alter table public.rb_groups enable row level security;
alter table public.rb_items  enable row level security;
revoke all on public.rb_config, public.rb_groups, public.rb_items from anon, authenticated;

-- コードと合言葉が合っていれば、グループのidを返す（合わなければ少し待ってからエラー）
create or replace function public.rb__group(p_code text, p_pass text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare g uuid;
begin
  select id into g from rb_groups
   where code = upper(trim(p_code)) and pass_hash = crypt(p_pass, pass_hash);
  if g is null then
    perform pg_sleep(0.6);
    raise exception 'RB_AUTH';
  end if;
  return g;
end $$;

-- グループを作る（作成キーが必要）。グループコードを返す
create or replace function public.rb_create_group(p_key text, p_name text, p_pass text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare k text; c text; i int;
  abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  select value into k from rb_config where key = 'create_key';
  if k is null or k <> crypt(coalesce(p_key,''), k) then
    perform pg_sleep(0.6);
    raise exception 'RB_KEY';
  end if;
  if char_length(trim(coalesce(p_name,''))) not between 1 and 40 then raise exception 'RB_NAME'; end if;
  if char_length(coalesce(p_pass,'')) not between 6 and 60 then raise exception 'RB_PASS'; end if;
  if (select count(*) from rb_groups) >= 200 then raise exception 'RB_FULL'; end if;
  loop
    c := '';
    for i in 1..6 loop
      c := c || substr(abc, 1 + floor(random() * 32)::int, 1);
    end loop;
    exit when not exists (select 1 from rb_groups where code = c);
  end loop;
  insert into rb_groups(code, name, pass_hash) values (c, trim(p_name), crypt(p_pass, gen_salt('bf')));
  return c;
end $$;

-- グループに入れるか確かめる。グループ名と件数を返す
create or replace function public.rb_join(p_code text, p_pass text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare g uuid;
begin
  g := rb__group(p_code, p_pass);
  return (select json_build_object('name', name, 'count', (select count(*) from rb_items where group_id = g))
            from rb_groups where id = g);
end $$;

-- 一覧（中身の本体は入れない。mine は自分が出したものかどうか）
create or replace function public.rb_list(p_code text, p_pass text, p_owner uuid)
returns table(id text, kind text, author text, summary jsonb, updated_at timestamptz, mine boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare g uuid;
begin
  g := rb__group(p_code, p_pass);
  return query
    select i.id, i.kind, i.author, i.summary, i.updated_at, (i.owner = p_owner)
      from rb_items i where i.group_id = g order by i.updated_at desc;
end $$;

-- 1件の中身
create or replace function public.rb_get(p_code text, p_pass text, p_id text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare g uuid; d jsonb;
begin
  g := rb__group(p_code, p_pass);
  select data into d from rb_items where group_id = g and id = p_id;
  if d is null then raise exception 'RB_GONE'; end if;
  return d;
end $$;

-- 出す・出しなおす（ほかの人が出したものは上書きできない）
create or replace function public.rb_put(p_code text, p_pass text, p_owner uuid, p_author text,
  p_id text, p_kind text, p_summary jsonb, p_data jsonb)
returns timestamptz language plpgsql security definer set search_path = public, extensions as $$
declare g uuid; o uuid; t timestamptz := now();
begin
  g := rb__group(p_code, p_pass);
  if p_kind not in ('card','plan') then raise exception 'RB_KIND'; end if;
  if char_length(coalesce(p_id,'')) not between 1 and 80 then raise exception 'RB_ID'; end if;
  if octet_length(p_data::text) > 1500000 or octet_length(p_summary::text) > 60000 then raise exception 'RB_BIG'; end if;
  select owner into o from rb_items where group_id = g and id = p_id;
  if o is not null and o <> p_owner then raise exception 'RB_NOT_OWNER'; end if;
  if o is null and (select count(*) from rb_items where group_id = g) >= 1000 then raise exception 'RB_FULL'; end if;
  insert into rb_items(group_id, id, kind, owner, author, summary, data, updated_at)
  values (g, p_id, p_kind, p_owner, left(coalesce(p_author,''), 30), p_summary, p_data, t)
  on conflict (group_id, id) do update
    set kind = excluded.kind, author = excluded.author, summary = excluded.summary,
        data = excluded.data, updated_at = excluded.updated_at;
  return t;
end $$;

-- 取り下げる（自分が出したものだけ）
create or replace function public.rb_remove(p_code text, p_pass text, p_owner uuid, p_id text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare g uuid; n int;
begin
  g := rb__group(p_code, p_pass);
  delete from rb_items where group_id = g and id = p_id and owner = p_owner;
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- グループを消す（作成キーが必要。中の共有物もいっしょに消える）
create or replace function public.rb_delete_group(p_key text, p_code text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare k text; n int;
begin
  select value into k from rb_config where key = 'create_key';
  if k is null or k <> crypt(coalesce(p_key,''), k) then
    perform pg_sleep(0.6);
    raise exception 'RB_KEY';
  end if;
  delete from rb_groups where code = upper(trim(p_code));
  get diagnostics n = row_count;
  return n > 0;
end $$;

-- 関数を使えるのは、アプリ（anon）からの呼び出しだけ。内部用の rb__group は外から呼べないようにする
revoke all on function public.rb__group(text, text) from public, anon, authenticated;
revoke all on function public.rb_create_group(text, text, text) from public;
revoke all on function public.rb_join(text, text) from public;
revoke all on function public.rb_list(text, text, uuid) from public;
revoke all on function public.rb_get(text, text, text) from public;
revoke all on function public.rb_put(text, text, uuid, text, text, text, jsonb, jsonb) from public;
revoke all on function public.rb_remove(text, text, uuid, text) from public;
revoke all on function public.rb_delete_group(text, text) from public;
grant execute on function public.rb_create_group(text, text, text) to anon, authenticated;
grant execute on function public.rb_join(text, text) to anon, authenticated;
grant execute on function public.rb_list(text, text, uuid) to anon, authenticated;
grant execute on function public.rb_get(text, text, text) to anon, authenticated;
grant execute on function public.rb_put(text, text, uuid, text, text, text, jsonb, jsonb) to anon, authenticated;
grant execute on function public.rb_remove(text, text, uuid, text) to anon, authenticated;
grant execute on function public.rb_delete_group(text, text) to anon, authenticated;

-- 作成キーを決める。下の ここに作成キー を、自分で決めた文字（8文字以上）に書きかえてから実行する。
-- 作成キーはグループを作る人だけが知っていればよい。人に配るのは「グループコード」と「合言葉」のほう。
insert into public.rb_config(key, value)
values ('create_key', extensions.crypt('ここに作成キー', extensions.gen_salt('bf')))
on conflict (key) do update set value = excluded.value;
