/**
 * 让测试里的 `env` 带上 Worker 的绑定类型。
 * 只在测试编译期生效，不影响打包（src/ 不引用这里）。
 */
import type { Env } from '../src/types';

declare module 'cloudflare:test' {
  interface ProvidedEnv extends Env {}
}
