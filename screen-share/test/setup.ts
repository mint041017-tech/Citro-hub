/**
 * 每个测试前的全局准备：启用 outbound fetch mock 并禁止真实外网。
 * 具体 mock 由各用例自己声明（这样未消费的 interceptor 不会互相干扰）。
 */
import { beforeEach } from 'vitest';
import { fetchMock } from 'cloudflare:test';

beforeEach(() => {
  fetchMock.activate();
  fetchMock.disableNetConnect();
});
