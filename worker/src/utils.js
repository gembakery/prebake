const encoder = new TextEncoder();

export async function timingSafeEqual(expected, actual) {
  const expectedBytes = encoder.encode(expected);
  const actualBytes = encoder.encode(actual);
  if (expectedBytes.byteLength !== actualBytes.byteLength) return false;
  return crypto.subtle.timingSafeEqual(expectedBytes, actualBytes);
}
