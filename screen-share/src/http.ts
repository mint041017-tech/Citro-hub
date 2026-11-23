/**
 * 异常 → 统一错误响应。
 *
 * Worker 路由（index.ts）与 DO 内部接口（room.ts）共用同一套
 * status / code / message 形状：ApiError（及跨 fetch 传回来的同类对象）
 * 自带 status / code，必须原样透传（满员 409、房间已结束 409、参数错 400…）；
 * 其余未知异常统一压成 500。响应体字段 `err` / `code` 是对外契约，不得改名。
 */

export interface ErrorBody {
  err: string;
  code?: string;
}

export function errorFrom(e: unknown): { status: number; body: ErrorBody } {
  if (e instanceof Error && 'status' in e) {
    const err = e as Error & { status: number; code?: string };
    return { status: err.status, body: { err: err.message, code: err.code } };
  }
  return { status: 500, body: { err: e instanceof Error ? e.message : String(e) } };
}
