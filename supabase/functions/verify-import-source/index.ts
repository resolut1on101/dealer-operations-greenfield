// Package 01 orchestration boundary: it hashes an already-uploaded private object.
// It deliberately does not parse XLSX files or write staging rows.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

type RequestBody = { batchId?: string }

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function corsText(body: string, status: number) {
  return new Response(body, { status, headers: { ...corsHeaders, 'Content-Type': 'text/plain; charset=utf-8' } })
}

function corsJson(body: Record<string, string>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function hexDigest(bytes: ArrayBuffer): Promise<string> {
  return crypto.subtle.digest('SHA-256', bytes).then((digest) =>
    Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join(''),
  )
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders })
  if (request.method !== 'POST') return corsText('Method not allowed', 405)
  const authorization = request.headers.get('Authorization')
  if (!authorization) return corsText('Unauthorized', 401)

  const url = Deno.env.get('SUPABASE_URL')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const callerClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authorization } },
  })
  const { data: { user }, error: userError } = await callerClient.auth.getUser()
  if (userError || !user) return corsText('Unauthorized', 401)

  const payload = await request.json() as RequestBody
  if (!payload.batchId) return corsText('batchId is required', 400)
  const serviceClient = createClient(url, serviceRoleKey)
  const { data: profile } = await serviceClient.from('user_profiles').select('role').eq('user_id', user.id).maybeSingle()
  if (profile?.role !== 'admin') return corsText('Forbidden', 403)

  const { data: batch, error: batchError } = await serviceClient
    .from('import_batches')
    .select('id, storage_bucket, storage_object_path, file_size_bytes, created_by, source_verified_at')
    .eq('id', payload.batchId)
    .eq('created_by', user.id)
    .maybeSingle()
  if (batchError || !batch) return corsText('Import batch not found', 404)
  if (batch.source_verified_at) return corsJson({ batchId: batch.id, status: 'verified' })

  const { data: source, error: sourceError } = await serviceClient.storage.from(batch.storage_bucket).download(batch.storage_object_path)
  if (sourceError || !source) return corsText('Source object not found', 409)
  const bytes = await source.arrayBuffer()
  if (bytes.byteLength !== batch.file_size_bytes) return corsText('Source object byte size changed', 409)
  const hash = await hexDigest(bytes)
  const { error: verificationError } = await serviceClient.rpc('verify_import_source_hash', {
    p_batch_id: batch.id,
    p_verified_file_hash: hash,
    p_verified_file_size_bytes: bytes.byteLength,
  })
  if (verificationError) return corsText('Source verification failed', 409)
  return corsJson({ batchId: batch.id, status: 'verified' })
})
