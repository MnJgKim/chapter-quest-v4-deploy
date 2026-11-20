/** Student-only approved lesson gateway. Not wired into production UI. */
export async function loadApprovedStudentLessons(supabase) {
  if (!supabase?.rpc) throw new TypeError('Supabase client required');
  // The server chooses the Seoul date and enforces weekday, queue and one-lesson limits.
  const scheduled = await supabase.rpc('cq_v4_ensure_today_approved_lesson');
  if (scheduled.error) throw new Error('Unable to verify today\'s approved lesson', { cause: scheduled.error });
  // A null scheduler result may mean today's lesson already exists or was submitted.
  // Never infer permission from the scheduler result; use the authorized list RPC.
  const listed = await supabase.rpc('cq_v4_my_released_chapters');
  if (listed.error) throw new Error('Unable to load authorized chapters', { cause: listed.error });
  if (!Array.isArray(listed.data)) throw new Error('Invalid authorized chapter response');
  return listed.data;
}

export async function requestApprovedPdfLink(supabase, chapterUuid) {
  if (!supabase?.functions?.invoke) throw new TypeError('Supabase Functions client required');
  if (typeof chapterUuid !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(chapterUuid)) {
    throw new TypeError('Valid chapter UUID required');
  }
  // The Edge Function rechecks JWT, enrollment, assignment and cq_v4_can_read_lesson.
  const response = await supabase.functions.invoke('cq-v4-pdf-link', { body: { chapter_uuid: chapterUuid } });
  if (response.error) throw new Error('PDF link request denied', { cause: response.error });
  const { signed_url: url, expires_at: expires } = response.data ?? {};
  if (typeof url !== 'string' || !url.startsWith('https://') || !Number.isFinite(Date.parse(expires)) || Date.parse(expires) <= Date.now()) {
    throw new Error('Invalid or expired PDF link');
  }
  return { url, expiresAt: expires };
}
