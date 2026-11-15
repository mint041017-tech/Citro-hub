import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

export default defineWorkersConfig({
  test: {
    include: ['test/**/*.test.ts'],
    setupFiles: ['./test/setup.ts'],
    testTimeout: 20_000,
    hookTimeout: 20_000,
    poolOptions: {
      workers: {
        main: './src/index.ts',
        // Windows 上并发跑多个 isolate 时 isolatedStorage 的回滚偶发失败
        // （EBUSY / 临时目录被占）。这里关掉隔离存储并串行复用同一个 worker，
        // 测试之间靠 beforeAll 建房间、用例内自清理来保证互不干扰。
        isolatedStorage: false,
        singleWorker: true,
        wrangler: { configPath: './wrangler.toml' },
        miniflare: {
          bindings: {
            CF_REALTIME_APP_ID: 'test-app-id',
            CF_REALTIME_APP_SECRET: 'test-app-secret',
            CF_TURN_KEY_ID: 'test-turn-id',
            CF_TURN_KEY_SECRET: 'test-turn-secret',
            ROOM_TOKEN_SECRET: 'test-room-secret',
            // 空字符串 = 未配置 trash.js，此时走本地 POC 的访客放行分支。
            TRASH_API_BASE: '',
            ROOM_MAX_VIEWERS: '50',
            ROOM_TTL_HOURS: '12',
            ROOM_TOKEN_TTL_HOURS: '2',
            HOST_GRACE_MINUTES: '5',
            CHAT_HISTORY_LIMIT: '50',
          },
          durableObjects: { ROOMS: 'Room' },
        },
      },
    },
  },
});
