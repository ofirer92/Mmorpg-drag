/** Token bucket per connection. `perSec` refill, `burst` capacity. Pure: pass the clock in. */
export interface Bucket {
  tokens: number;
  last: number;
}
export function newBucket(burst: number, now: number): Bucket {
  return { tokens: burst, last: now };
}
export function take(b: Bucket, perSec: number, burst: number, now: number): boolean {
  const elapsed = Math.max(0, now - b.last) / 1000;
  b.tokens = Math.min(burst, b.tokens + elapsed * perSec);
  b.last = now;
  if (b.tokens < 1) return false;
  b.tokens -= 1;
  return true;
}
