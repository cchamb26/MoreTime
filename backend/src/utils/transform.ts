/* eslint-disable @typescript-eslint/no-explicit-any */

/** Convert snake_case DB rows to camelCase for the API response. */
export function toCamel(obj: any): any {
  if (obj === null || obj === undefined) return null;
  if (Array.isArray(obj)) return obj.map(toCamel);
  if (typeof obj !== 'object' || obj instanceof Date) return obj;
  return Object.fromEntries(
    Object.entries(obj).map(([key, val]) => [
      key.replace(/_([a-z])/g, (_: string, c: string) => c.toUpperCase()),
      val !== null && typeof val === 'object' && !Array.isArray(val) && !(val instanceof Date)
        ? toCamel(val)
        : val,
    ]),
  );
}

/** Convert camelCase request body to snake_case for Supabase inserts/updates. */
export function toSnake(obj: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(obj).map(([key, val]) => [
      key.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`),
      val,
    ]),
  );
}
