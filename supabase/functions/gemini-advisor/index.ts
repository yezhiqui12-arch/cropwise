// WormWise advisor protection v1. JavaScript-compatible TypeScript for mock tests.
const defaultModels = [
  'gemini-3.6-flash', 'gemini-3.5-flash-lite',
  'gemini-3.1-flash-lite', 'gemini-3-flash-preview',
];
const modelName = /^gemini-[0-9]+(?:\.[0-9]+)?-flash(?:-lite)?(?:-preview)?$/;
const jsonHeaders = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
const maxBytes = 131072;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function failure(status, error, code, retryAfter = null) {
  const headers = { ...jsonHeaders };
  if (retryAfter != null) headers['Retry-After'] = String(retryAfter);
  return Response.json({ error, code, terminal: true }, { status, headers });
}
function configuredModels() {
  const configured = Deno.env.get('GEMINI_ADVISOR_MODELS');
  if (configured == null || configured.trim() === '') return defaultModels;
  const models = configured.split(',').map((model) => model.trim());
  if (models.length > 4 || new Set(models).size !== models.length ||
      models.some((model) => !modelName.test(model))) throw new Error('Invalid model policy');
  return models;
}
function object(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value);
}
function keys(value, allowed) {
  if (!object(value) || Object.keys(value).some((key) => !allowed.includes(key)))
    throw new Error('Unsupported request settings');
}
async function readPayload(request) {
  const declared = Number(request.headers.get('content-length'));
  if (declared > maxBytes) throw new RangeError('Request too large');
  if (!request.body) throw new Error('Missing body');
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('Body timeout')), 5000);
  });
  try {
    while (true) {
      const chunk = await Promise.race([reader.read(), timeout]);
      if (chunk.done) break;
      size += chunk.value.byteLength;
      if (size > maxBytes) throw new RangeError('Request too large');
      chunks.push(chunk.value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } finally {
    clearTimeout(timer);
    await reader.cancel().catch(() => {});
  }
}
function validatedBody(payload) {
  keys(payload, ['model', 'body']);
  if (payload.model != null && (typeof payload.model !== 'string' ||
      payload.model.length > 80 || !modelName.test(payload.model))) throw new Error('Invalid model');
  const body = payload.body;
  keys(body, ['contents', 'system_instruction', 'generationConfig', 'store']);
  if (body.store != null && body.store !== false) throw new Error('Unsupported storage');
  let chars = 0;
  const parts = (value) => {
    if (!Array.isArray(value) || value.length === 0 || value.length > 64)
      throw new Error('Invalid parts');
    return value.map((part) => {
      keys(part, ['text']);
      if (typeof part.text !== 'string') throw new Error('Only text is supported');
      chars += part.text.length;
      if (chars > 80000) throw new RangeError('Prompt too large');
      return { text: part.text };
    });
  };
  if (!Array.isArray(body.contents) || body.contents.length === 0 || body.contents.length > 32)
    throw new Error('Invalid contents');
  const contents = body.contents.map((content) => {
    keys(content, ['role', 'parts']);
    if (content.role != null && !['user', 'model'].includes(content.role)) throw new Error('Invalid role');
    return { role: content.role ?? 'user', parts: parts(content.parts) };
  });
  if (contents.at(-1).role !== 'user' || !contents.some((c) => c.parts.some((p) => p.text.trim())))
    throw new Error('Missing user input');
  const forwarded = { contents };
  if (body.system_instruction != null) {
    keys(body.system_instruction, ['parts']);
    forwarded.system_instruction = { parts: parts(body.system_instruction.parts) };
  }
  const config = body.generationConfig ?? {};
  keys(config, ['temperature', 'maxOutputTokens', 'responseMimeType', 'responseJsonSchema']);
  if (config.temperature != null && (typeof config.temperature !== 'number' ||
      !Number.isFinite(config.temperature) || config.temperature < 0 || config.temperature > 1))
    throw new Error('Invalid temperature');
  if (config.maxOutputTokens != null && (!Number.isInteger(config.maxOutputTokens) || config.maxOutputTokens < 1))
    throw new Error('Invalid output limit');
  if (config.responseMimeType != null && config.responseMimeType !== 'application/json')
    throw new Error('Unsupported response format');
  if (config.responseJsonSchema != null) {
    if (!object(config.responseJsonSchema) || config.responseMimeType !== 'application/json' ||
        JSON.stringify(config.responseJsonSchema).length > 16384) throw new Error('Invalid schema');
    let nodes = 0;
    const visit = (value, depth) => {
      if (++nodes > 2048 || depth > 16) throw new Error('Schema too complex');
      if (value && typeof value === 'object') for (const child of Object.values(value)) visit(child, depth + 1);
    };
    visit(config.responseJsonSchema, 0);
  }
  forwarded.generationConfig = {
    ...config, maxOutputTokens: Math.min(config.maxOutputTokens ?? 1536, 2500), candidateCount: 1,
  };
  return forwarded;
}
function retryable(status, message) {
  return [403, 404, 408, 429, 500, 502, 503, 504].includes(status) ||
    (status === 400 && /model.*(unavailable|unsupported|not found|deprecated)/i.test(message));
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return failure(405, 'Method not allowed.', 'method_not_allowed');
  const authorization = request.headers.get('authorization');
  if (!authorization || !/^Bearer [^\s]+$/i.test(authorization) || authorization.length > 8192)
    return failure(401, 'Please reconnect your account and try again.', 'authentication_required');
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const geminiKey = Deno.env.get('GEMINI_API_KEY');
  if (!url || !serviceKey || !geminiKey)
    return failure(503, 'The AI service is not configured.', 'service_not_configured');
  const deadline = Date.now() + 29000;
  let user;
  try {
    // Auth server validates the signed token; public/service keys are not user sessions.
    const auth = await fetch(`${url}/auth/v1/user`, {
      headers: { apikey: serviceKey, Authorization: authorization }, signal: AbortSignal.timeout(4000),
    });
    if (auth.status === 401 || auth.status === 403)
      return failure(401, 'Please reconnect your account and try again.', 'authentication_required');
    if (!auth.ok) throw new Error('Auth unavailable');
    user = await auth.json();
    if (!uuid.test(user?.id) || user.role !== 'authenticated')
      return failure(401, 'Please reconnect your account and try again.', 'authentication_required');
  } catch (_) { return failure(503, 'Account verification is temporarily unavailable.', 'authentication_unavailable'); }
  let payload, body, models;
  try { payload = await readPayload(request); body = validatedBody(payload); }
  catch (error) {
    return error instanceof RangeError
      ? failure(413, 'This AI request is too large. Please shorten it and try again.', 'request_too_large')
      : failure(400, 'Invalid AI request.', 'invalid_request');
  }
  try { models = configuredModels(); }
  catch (_) { return failure(503, 'The AI model policy is invalid.', 'invalid_model_policy'); }
  const fast = payload.model?.endsWith('-flash-lite');
  const ordered = fast
    ? [...models.filter((model) => model.endsWith('-flash-lite')), ...models.filter((model) => !model.endsWith('-flash-lite'))]
    : models;
  for (const model of ordered) {
    const remaining = deadline - Date.now();
    if (remaining < 1500) break;
    // Persisted, atomic reservation BEFORE EVERY provider attempt, including fallbacks.
    try {
      const response = await fetch(`${url}/rest/v1/rpc/reserve_advisor_attempt`, {
        method: 'POST', headers: {
          apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json',
        }, body: JSON.stringify({ p_user_id: user.id }), signal: AbortSignal.timeout(Math.min(3000, remaining)),
      });
      if (!response.ok) throw new Error('Quota unavailable');
      const quota = await response.json();
      if (quota?.allowed === false && Number.isInteger(quota.retry_after) && quota.retry_after > 0) {
        return failure(429, quota.scope === 'project'
          ? 'The Advisor is busy. Please try again later.'
          : 'You have reached the Advisor request limit. Please try again later.',
          'advisor_rate_limit', quota.retry_after);
      }
      if (quota?.allowed !== true) throw new Error('Invalid quota result');
    } catch (_) { return failure(503, 'The Advisor request limit could not be checked. Please try again later.', 'quota_unavailable'); }
    if (deadline - Date.now() < 500) break;
    try {
      const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': geminiKey },
        body: JSON.stringify(body), signal: AbortSignal.timeout(Math.min(8000, deadline - Date.now())),
      });
      const responseBody = await response.json().catch(() => null);
      if (response.ok && object(responseBody))
        return Response.json({ ...responseBody, wormwiseModel: model }, { headers: jsonHeaders });
      const message = typeof responseBody?.error?.message === 'string' ? responseBody.error.message : '';
      if (!response.ok && !retryable(response.status, message))
        return failure(502, 'The AI provider could not process this request. Please try again.', 'provider_rejected');
    } catch (_) { /* A timeout may still be billed, so never refund the reservation. */ }
  }
  return failure(503, 'The AI provider is temporarily unavailable. Please try again later.', 'provider_unavailable');
});
