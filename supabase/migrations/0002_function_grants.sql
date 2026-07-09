-- Functions are executable by PUBLIC by default; revoking only from anon is
-- not enough since anon inherits the PUBLIC grant.
revoke execute on function public.roomies_create_household(text, text) from public, anon;
revoke execute on function public.roomies_join_household(text, text) from public, anon;
revoke execute on function public.roomies_is_member(uuid) from public, anon;

grant execute on function public.roomies_create_household(text, text) to authenticated;
grant execute on function public.roomies_join_household(text, text) to authenticated;
-- is_member is invoked from RLS policies evaluated as the querying role.
grant execute on function public.roomies_is_member(uuid) to authenticated;
