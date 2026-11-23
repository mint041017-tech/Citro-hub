/**
 * trash.js 会话校验。
 *
 * App 侧的登录态是 trash.js 发的 30 天 token（Cookie 主、X-Trash-Token 兜底）。
 * Worker 不共享 trash.js 的内存会话表，所以只能服务端对服务端问一下
 * `GET /api/auth/me`，让它告诉我们这个 token 是谁。
 *
 * 结果会缓存很短时间（默认 60s）：创建 / 加入房间不是高频操作，
 * 但前端重试和多端同时加入会重复问，缓存能明显减少 trash.js 的压力。
 */

import { ERR } from './types';

export interface TrashUser {
  name: string;
  token: string;
}

/** 缓存有效期：创建 / 加入房间不是高频操作，但前端重试和多端同时加入会重复问。 */
const CACHE_TTL_MS = 60_000;

/** 内存缓存：token → 用户。进程级，够用且没有额外依赖。 */
const cache = new Map<string, { user: TrashUser; exp: number }>();

export async function verifyTrashToken(
  env: { TRASH_API_BASE?: string; TRASH_API_SECRET?: string },
  token: string | null,
): Promise<TrashUser> {
  if (!token) throw ERR.noAuth();
  const apiBase = env.TRASH_API_BASE;
  if (!apiBase) {
    // 本地 POC：没有 trash.js 可问时，放行一个占位身份。
    // 生产必须配置 TRASH_API_BASE，否则任何人都能创建房间。
    return { name: `guest_${token.slice(0, 6)}`, token };
  }
  const hit = cache.get(token);
  if (hit && hit.exp > Date.now()) return hit.user;

  const url = `${apiBase.replace(/\/$/, '')}/api/auth/me`;
  const res = await fetch(url, {
    headers: {
      'X-Trash-Token': token,
      ...(env.TRASH_API_SECRET ? { 'X-Trash-Api-Secret': env.TRASH_API_SECRET } : {}),
    },
  }).catch(() => null);
  if (!res || res.status === 401 || res.status === 403) throw ERR.noAuth('登录已失效，请重新登录');
  if (!res.ok) throw ERR.sfu('登录服务暂不可用');
  const data = (await res.json().catch(() => null)) as { user?: { name?: string } | null } | null;
  const name = data?.user?.name;
  if (!name) throw ERR.noAuth('登录已失效，请重新登录');

  const user: TrashUser = { name, token };
  cache.set(token, { user, exp: Date.now() + CACHE_TTL_MS });
  return user;
}
