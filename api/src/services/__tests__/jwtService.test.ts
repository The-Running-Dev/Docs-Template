import { describe, it, expect } from 'vitest';
import { signAccessToken, verifyToken } from '../jwtService';

describe('JWT Service', () => {
  it('signs and verifies a token', () => {
    const payload = { sub: 'user1', username: 'test', roles: ['admin'] };
    const token = signAccessToken(payload, 'testsecret', '1h');
    const decoded = verifyToken(token, 'testsecret');
    expect(typeof token).toBe('string');
    expect(decoded).toMatchObject(payload);
  });

  it('returns null for invalid token', () => {
    expect(verifyToken('invalid.token', 'testsecret')).toBeNull();
  });
});
