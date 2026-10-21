'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

test('dashboard refuses to start auth without configuration', async () => {
  const { authenticate } = require('../src/dashboard/server');
  await assert.rejects(() => authenticate({ headers: {} }), { status: 503 });
});
