-- ============================================================================
--  Phostory — email 완전 차단 (#3) + 관리자 RPC (#5 권한 재검증 포함)
-- ============================================================================
--  목적 : RLS 는 '행'만 막고 '열(email)'은 못 막습니다. 로그인한 사용자가
--         REST 로 /profiles?select=email 을 직접 호출하면 남의 email 이 보입니다.
--         이를 막기 위해 email 컬럼 SELECT 권한을 없애고(STEP 2), 관리자 화면은
--         SECURITY DEFINER RPC 로만 email 을 받도록 전환합니다.
--
--  ⚠️ 반드시 STEP 순서대로! 순서를 어기면 관리자 화면이 잠깐 깨집니다.
--     STEP 1 (지금 실행) → 코드 배포 → 관리자 화면 테스트 → STEP 2 (실행)
-- ============================================================================


-- ============================================================================
--  STEP 1 — 지금 실행  (관리자용 RPC 생성)
--  이 시점엔 기존 관리자 화면(select '*')도 그대로 동작합니다. 안전.
-- ============================================================================

-- (1) staff 판별 헬퍼
create or replace function public.is_staff()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role in ('admin','developer','operator')
  );
$$;

-- (2) 사용자 목록 — email 포함.
--     'returns setof public.profiles' 라서 반환 객체 구조가 기존 select('*')와
--     동일 → 프론트 코드는 .from().select() 를 .rpc() 로 바꾸기만 하면 됩니다.
--     SECURITY DEFINER 라 STEP 2 의 email 컬럼 권한 제한을 우회해 정상 반환합니다.
create or replace function public.admin_list_users()
returns setof public.profiles
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then raise exception 'Not authorized'; end if;
  return query
    select * from public.profiles
    where deleted_at is null
    order by created_at desc;
end;
$$;

-- (3) 단일 사용자 상세
create or replace function public.admin_get_user(target_id uuid)
returns setof public.profiles
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then raise exception 'Not authorized'; end if;
  return query select * from public.profiles where id = target_id;
end;
$$;

-- (4) 사용자 검색 — username / email / id 무엇으로든 매칭
create or replace function public.admin_find_user(q text)
returns setof public.profiles
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then raise exception 'Not authorized'; end if;
  return query
    select * from public.profiles
    where username = replace(q, '@', '')
       or email = q
       or id::text = q
    limit 5;
end;
$$;

-- (5) anon 은 이 RPC 들을 실행조차 못 하도록 (staff 체크가 내부에 있지만 이중방어)
revoke execute on function public.admin_list_users()      from anon;
revoke execute on function public.admin_get_user(uuid)    from anon;
revoke execute on function public.admin_find_user(text)   from anon;

-- (6) 로그인용 username→email 변환 RPC (ID 기반 로그인 유지에 필수)
--     ⚠️ 이 함수는 로그인 전(anon)에도 호출돼야 하므로 email 을 반환합니다.
--     즉 "username 을 정확히 아는 경우" 그 사용자의 email 1건은 확인 가능합니다
--     (Supabase 로그인이 email 기반이라 불가피). 하지만 STEP 2 적용 후에는
--     /profiles?select=email 로 '전체 email 을 한 번에 덤프'하는 건 차단됩니다.
create or replace function public.get_login_email(p_username text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select email into v_email
  from public.profiles
  where username = replace(p_username, '@', '') and deleted_at is null
  limit 1;
  return v_email;   -- 없으면 null 반환
end;
$$;


-- ============================================================================
--  STEP 2 — 코드(admin RPC 전환)를 배포하고, 관리자 화면(목록/상세/검색/
--  역할변경/삭제/비번재설정)이 전부 정상 동작하는지 확인한 "뒤에만" 실행!
--  이걸 실행하면 email 직접 조회가 최종 차단됩니다.
--  아래 3줄의 맨 앞 '-- ' 를 지우고 실행하세요.
-- ============================================================================
-- revoke select on public.profiles from anon, authenticated;
-- grant  select (id, username, bio, avatar_url, role, created_at)
--        on public.profiles to anon, authenticated;

--  확인: email 이 정말 막혔는지
--    select has_column_privilege('authenticated','public.profiles','email','SELECT');
--    → false 여야 완전 차단 성공


-- ============================================================================
--  #5 — 관리자 삭제 RPC 권한 재검증 (확인용)
-- ============================================================================
--  기존 delete_user_by_admin(...) 함수가 '호출자가 staff 인지' 검증하는지
--  반드시 확인하세요. 검증이 없으면 아무나 남을 삭제할 수 있습니다.
--
--  (a) 현재 정의 확인:
--      select pg_get_functiondef('public.delete_user_by_admin(uuid)'::regprocedure);
--
--  (b) 함수 본문 맨 앞에 아래 가드가 없으면 추가하세요:
--      if not public.is_staff() then raise exception 'Not authorized'; end if;
-- ============================================================================
