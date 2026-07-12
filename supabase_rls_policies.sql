-- ============================================================================
--  Phostory — Supabase RLS & 권한(Privilege) 하드닝 스크립트
-- ============================================================================
--  목적 : anon key 가 공개돼 있어도(정상) 데이터가 안전하도록 RLS 를 건다.
--  실행 : Supabase Dashboard → SQL Editor → New query → 전체 붙여넣기 → Run
--  성질 : 여러 번 실행해도 안전(idempotent). 'drop ... if exists' 사용.
--
--  ⚠️ 실행 전 확인 — 아래 컬럼명이 실제 테이블과 같은지 (Table Editor 에서):
--     profiles : id(uuid), username, email, bio, avatar_url, role, created_at, deleted_at
--     posts    : id, user_id(uuid), title, image_url, is_public, created_at, deleted_at
--     likes    : user_id(uuid), post_id
--  role 값 : 'user' | 'official' | 'operator' | 'admin' | 'developer'
--            (운영진 staff = operator / admin / developer)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) RLS 활성화  ★가장 중요★
--    이게 꺼져 있으면 anon key 로 모든 행을 읽고/쓰고/지울 수 있습니다.
-- ----------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.posts    enable row level security;
alter table public.likes    enable row level security;


-- ----------------------------------------------------------------------------
-- 2) PROFILES — 읽기/쓰기 정책
-- ----------------------------------------------------------------------------
-- 읽기: 삭제 안 된 프로필은 누구나(공개 프로필 페이지 /username 용)
drop policy if exists "profiles_public_read" on public.profiles;
create policy "profiles_public_read" on public.profiles
  for select using (deleted_at is null);

-- 생성: 본인 id 로만
drop policy if exists "profiles_insert_self" on public.profiles;
create policy "profiles_insert_self" on public.profiles
  for insert with check ((select auth.uid()) = id);

-- 수정: 본인만 (단, role 변경은 3)번 트리거가 추가로 검증)
drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self" on public.profiles
  for update using ((select auth.uid()) = id)
             with check ((select auth.uid()) = id);

-- 운영진(staff)은 모든 프로필 수정 가능(역할 부여/차단/관리)
drop policy if exists "profiles_update_staff" on public.profiles;
create policy "profiles_update_staff" on public.profiles
  for update using (
    exists (select 1 from public.profiles p
            where p.id = (select auth.uid())
              and p.role in ('admin','developer','operator'))
  );


-- ----------------------------------------------------------------------------
-- 3) 권한 상승(Privilege Escalation) 차단 트리거   ← 감사항목 #1 (Critical)
--    일반 사용자가 자기 role 을 'admin' 등으로 올리는 것을 서버에서 원천 차단.
--    운영진이 바꾸는 경우만 통과 → 기존 관리자 화면 코드는 그대로 동작합니다.
-- ----------------------------------------------------------------------------
create or replace function public.enforce_role_change_is_staff()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role then
    if not exists (
      select 1 from public.profiles
      where id = (select auth.uid())
        and role in ('admin','developer','operator')
    ) then
      raise exception 'Not authorized to change role (privilege escalation blocked)';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_role_change on public.profiles;
create trigger trg_enforce_role_change
  before update of role on public.profiles
  for each row execute function public.enforce_role_change_is_staff();


-- ----------------------------------------------------------------------------
-- 4) POSTS — 읽기/쓰기 정책
-- ----------------------------------------------------------------------------
-- 읽기: 공개글(삭제 안 됨)은 누구나 / 본인 글은 전부
drop policy if exists "posts_read_public_or_own" on public.posts;
create policy "posts_read_public_or_own" on public.posts
  for select using (
    (is_public = true and deleted_at is null)
    or (select auth.uid()) = user_id
  );

-- 생성/수정/삭제: 본인 것만
drop policy if exists "posts_insert_own" on public.posts;
create policy "posts_insert_own" on public.posts
  for insert with check ((select auth.uid()) = user_id);

drop policy if exists "posts_update_own" on public.posts;
create policy "posts_update_own" on public.posts
  for update using ((select auth.uid()) = user_id)
             with check ((select auth.uid()) = user_id);

drop policy if exists "posts_delete_own" on public.posts;
create policy "posts_delete_own" on public.posts
  for delete using ((select auth.uid()) = user_id);

-- 운영진은 모든 글 관리(신고 처리/강제 삭제)
drop policy if exists "posts_manage_staff" on public.posts;
create policy "posts_manage_staff" on public.posts
  for update using (
    exists (select 1 from public.profiles p
            where p.id = (select auth.uid())
              and p.role in ('admin','developer','operator'))
  );


-- ----------------------------------------------------------------------------
-- 5) LIKES — 정책
-- ----------------------------------------------------------------------------
-- 읽기: 좋아요 수 표시를 위해 전체 허용
drop policy if exists "likes_read_all" on public.likes;
create policy "likes_read_all" on public.likes
  for select using (true);

-- 추가/삭제: 본인 것만 (남 대신 좋아요/취소 불가)
drop policy if exists "likes_insert_own" on public.likes;
create policy "likes_insert_own" on public.likes
  for insert with check ((select auth.uid()) = user_id);

drop policy if exists "likes_delete_own" on public.likes;
create policy "likes_delete_own" on public.likes
  for delete using ((select auth.uid()) = user_id);


-- ============================================================================
-- 6) (선택·권장) email 직접 노출 완전 차단   ← 감사항목 #3 강화
--    RLS 는 '행'만 막고 '열(email)'은 못 막습니다. 아래를 실행하면 anon /
--    로그인 사용자가 profiles.email 을 직접 SELECT 하는 것을 차단합니다.
--
--    ⚠️ 이걸 적용하면 관리자 화면의 email 표시가 동작하려면 7)번 RPC 로
--       바꿔야 합니다(코드 수정 필요). 준비 전이면 이 6)·7) 블록은
--       주석(--) 그대로 두고 나중에 함께 적용하세요.
-- ----------------------------------------------------------------------------
-- revoke select on public.profiles from anon, authenticated;
-- grant  select (id, username, bio, avatar_url, role, created_at)
--        on public.profiles to anon, authenticated;


-- ----------------------------------------------------------------------------
-- 7) (선택·권장) 운영진 전용 사용자 목록 RPC (6번과 짝)
--    email 은 이 함수로만 노출. 호출자가 staff 인지 서버에서 검증.
-- ----------------------------------------------------------------------------
-- create or replace function public.admin_list_users()
-- returns table (id uuid, username text, email text, role text, created_at timestamptz)
-- language plpgsql security definer set search_path = public as $$
-- begin
--   if not exists (select 1 from public.profiles
--                  where id = (select auth.uid())
--                    and role in ('admin','developer','operator')) then
--     raise exception 'Not authorized';
--   end if;
--   return query
--     select p.id, p.username, p.email, p.role, p.created_at
--     from public.profiles p where p.deleted_at is null;
-- end; $$;


-- ============================================================================
-- 8) 검증 — 실행 후 반드시 확인
-- ============================================================================
-- (a) RLS 켜졌는지:
--     select tablename, rowsecurity from pg_tables
--     where schemaname='public' and tablename in ('profiles','posts','likes');
--     → 세 줄 모두 rowsecurity = true 여야 함
--
-- (b) Dashboard → Advisors → "Security Advisor" 실행 → 남은 경고 0 확인
--
-- (c) 권한상승 차단 테스트(선택): 일반 계정 토큰으로
--       update profiles set role='admin' where id='<본인id>';
--     → "privilege escalation blocked" 에러가 나면 정상.
-- ============================================================================
