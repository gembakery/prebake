const encoder = new TextEncoder();

export async function timingSafeEqual(expected, actual) {
  const expectedBytes = encoder.encode(expected);
  const actualBytes = encoder.encode(actual);
  if (expectedBytes.byteLength !== actualBytes.byteLength) return false;
  return crypto.subtle.timingSafeEqual(expectedBytes, actualBytes);
}

export async function requireAuth(request, env) {
  const authHeader = request.headers.get("Authorization") || "";
  if (!(await timingSafeEqual(`Bearer ${env.API_KEY}`, authHeader))) {
    return new Response("Unauthorized", { status: 401 });
  }
  return null;
}
