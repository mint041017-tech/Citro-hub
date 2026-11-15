import { describe, expect, it } from 'vitest';
import { signRoomToken, verifyRoomToken, extractBearer } from '../src/token';
import { ERR } from '../src/types';

const SECRET = 'unit-test-secret';

describe('room token', () => {
  it('签发后能原样验回，并带上房间 / 用户 / 角色', async () => {
    const token = await signRoomToken(
      { v: 1, roomId: '123456-ab', roomCode: '123456', uid: 'alice', name: '爱丽丝', role: 'host' },
      SECRET,
      3600,
    );
    const payload = await verifyRoomToken(token, SECRET);
    expect(payload.roomId).toBe('123456-ab');
    expect(payload.uid).toBe('alice');
    expect(payload.role).toBe('host');
    expect(payload.exp).toBeGreaterThan(Math.floor(Date.now() / 1000));
  });

  it('换一个密钥就验不过', async () => {
    const token = await signRoomToken(
      { v: 1, roomId: 'r1', roomCode: '111111', uid: 'bob', name: '鲍勃', role: 'viewer' },
      SECRET,
      3600,
    );
    await expect(verifyRoomToken(token, 'other-secret')).rejects.toThrow();
  });

  it('过期后拒绝', async () => {
    const token = await signRoomToken(
      { v: 1, roomId: 'r1', roomCode: '111111', uid: 'bob', name: '鲍勃', role: 'viewer' },
      SECRET,
      -10,
    );
    await expect(verifyRoomToken(token, SECRET)).rejects.toMatchObject({ status: 401 });
  });

  it('篡改 payload 会被签名拦下', async () => {
    const token = await signRoomToken(
      { v: 1, roomId: 'r1', roomCode: '111111', uid: 'bob', name: '鲍勃', role: 'viewer' },
      SECRET,
      3600,
    );
    const [h, p, s] = token.split('.');
    const forged = `${h}.${p.replace(/.$/, 'X')}.${s}`;
    await expect(verifyRoomToken(forged, SECRET)).rejects.toMatchObject({ status: 400 });
  });

  it('从 Authorization 头里取 Bearer', () => {
    const req = new Request('https://x/api/rooms', {
      headers: { Authorization: 'Bearer abc.def.ghi' },
    });
    expect(extractBearer(req)).toBe('abc.def.ghi');
    expect(extractBearer(new Request('https://x/'))).toBeNull();
  });

  it('错误码形状统一：status + code + message', () => {
    const e = ERR.roomFull();
    expect(e.status).toBe(409);
    expect(e.code).toBe('room_full');
    expect(e.message).toContain('满');
  });
});
