const express = require('express');
const multer  = require('multer');
const path    = require('path');
const { pool } = require('../db/client');

const router = express.Router();

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, process.env.UPLOAD_DIR || '/uploads');
  },
  filename: (req, file, cb) => {
    const unique = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    cb(null, `${unique}${path.extname(file.originalname)}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10 MB
  fileFilter: (req, file, cb) => {
    const allowed = ['.pdf', '.png', '.jpg', '.jpeg', '.txt', '.md'];
    if (allowed.includes(path.extname(file.originalname).toLowerCase())) {
      cb(null, true);
    } else {
      cb(new Error('Unsupported file type'));
    }
  },
});

// GET /api/tasks
router.get('/', async (req, res) => {
  const { rows } = await pool.query(
    'SELECT * FROM tasks ORDER BY created_at DESC'
  );
  res.json(rows);
});

// GET /api/tasks/:id
router.get('/:id', async (req, res) => {
  const { rows } = await pool.query(
    'SELECT * FROM tasks WHERE id = $1',
    [req.params.id]
  );
  if (!rows.length) return res.status(404).json({ error: 'Task not found' });
  res.json(rows[0]);
});

// POST /api/tasks
router.post('/', async (req, res) => {
  const { title, description, status = 'todo' } = req.body;
  if (!title) return res.status(400).json({ error: 'title is required' });

  const { rows } = await pool.query(
    `INSERT INTO tasks (title, description, status)
     VALUES ($1, $2, $3) RETURNING *`,
    [title, description, status]
  );
  res.status(201).json(rows[0]);
});

// PUT /api/tasks/:id
router.put('/:id', async (req, res) => {
  const { title, description, status } = req.body;
  const { rows } = await pool.query(
    `UPDATE tasks
     SET title = COALESCE($1, title),
         description = COALESCE($2, description),
         status = COALESCE($3, status),
         updated_at = NOW()
     WHERE id = $4
     RETURNING *`,
    [title, description, status, req.params.id]
  );
  if (!rows.length) return res.status(404).json({ error: 'Task not found' });
  res.json(rows[0]);
});

// DELETE /api/tasks/:id
router.delete('/:id', async (req, res) => {
  const { rowCount } = await pool.query(
    'DELETE FROM tasks WHERE id = $1',
    [req.params.id]
  );
  if (!rowCount) return res.status(404).json({ error: 'Task not found' });
  res.status(204).end();
});

// POST /api/tasks/:id/attachments
router.post('/:id/attachments', upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

  const { rows } = await pool.query(
    `UPDATE tasks SET attachment = $1, updated_at = NOW()
     WHERE id = $2 RETURNING *`,
    [req.file.filename, req.params.id]
  );
  if (!rows.length) return res.status(404).json({ error: 'Task not found' });
  res.json(rows[0]);
});

module.exports = router;
