'use strict';
require('express-async-errors');

const express      = require('express');
const morgan       = require('morgan');
const helmet       = require('helmet');
const client       = require('prom-client');
const { migrate }  = require('./db/client');
const tasksRouter  = require('./routes/tasks');

const app  = express();
const PORT = parseInt(process.env.APP_PORT || '3000', 10);

// ─── Prometheus metrics ───────────────────────────────────────────────────────
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name:    'http_request_duration_seconds',
  help:    'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
  registers: [register],
});

// ─── Middleware ───────────────────────────────────────────────────────────────
app.use(helmet());
app.use(morgan('combined'));
app.use(express.json());
app.use(express.static('src/public'));

app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    end({ method: req.method, route: req.path, status_code: res.statusCode });
  });
  next();
});

// ─── Routes ───────────────────────────────────────────────────────────────────
app.use('/api/tasks', tasksRouter);

app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

app.get('/ready', async (req, res) => {
  const { pool } = require('./db/client');
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (err) {
    res.status(503).json({ status: 'not ready', error: err.message });
  }
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// ─── Error handler ────────────────────────────────────────────────────────────
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

// ─── Boot ─────────────────────────────────────────────────────────────────────
async function start() {
  await migrate();
  app.listen(PORT, () => {
    console.log(`TaskManager listening on :${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  });
}

start().catch(err => {
  console.error('Fatal startup error:', err);
  process.exit(1);
});
