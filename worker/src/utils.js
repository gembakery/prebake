const encoder = new TextEncoder();

export async function timingSafeEqual(expected, actual) {
  const expectedBytes = encoder.encode(expected);
  const actualBytes = encoder.encode(actual);
  if (expectedBytes.byteLength !== actualBytes.byteLength) return false;
  return crypto.subtle.timingSafeEqual(expectedBytes, actualBytes);
}

export function createSizeLimitedStream(body, maxBytes) {
  let bytesReceived = 0;

  const { readable, writable } = new TransformStream({
    transform(chunk, controller) {
      bytesReceived += chunk.byteLength;
      if (bytesReceived > maxBytes) {
        controller.error(new RangeError("Body exceeds size limit"));
        return;
      }
      controller.enqueue(chunk);
    },
  });

  body.pipeTo(writable).catch(() => {});

  return readable;
}
