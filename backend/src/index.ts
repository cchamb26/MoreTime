import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { errorHandler } from './middleware/errorHandler.js';
import { prisma } from './utils/db.js';

import authRoutes from './routes/auth.js';
import courseRoutes from './routes/courses.js';
import taskRoutes from './routes/tasks.js';
import scheduleRoutes from './routes/schedule.js';
import chatRoutes from './routes/chat.js';
import fileRoutes from './routes/files.js';
import voiceRoutes from './routes/voice.js';

const app = express();

// Global middleware
app.use(cors());
app.use(express.json({ limit: '1mb' }));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(limiter);

// AI-specific rate limiting (more restrictive)
const aiLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 20,
  message: { error: 'Too many AI requests, please slow down' },
});

// Routes
app.use('/auth', authRoutes);
app.use('/courses', courseRoutes);
app.use('/tasks', taskRoutes);
app.use('/schedule', scheduleRoutes);
app.use('/chat', aiLimiter, chatRoutes);
app.use('/files', fileRoutes);
app.use('/voice', aiLimiter, voiceRoutes);

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Dev bypass: seed the dev user on startup so all authed routes work
if (process.env.DEV_BYPASS_AUTH === 'true') {
  const DEV_USER_ID = 'dev-bypass-user';
  prisma.user
    .upsert({
      where: { id: DEV_USER_ID },
      update: {},
      create: {
        id: DEV_USER_ID,
        email: 'dev@moretime.local',
        name: 'Dev User',
        passwordHash: 'bypass',
        timezone: 'America/New_York',
      },
    })
    .then(() => console.log('Dev bypass auth enabled — dev user seeded'))
    .catch((err: unknown) => console.error('Failed to seed dev user:', err));
}

// Error handler (must be last)
app.use(errorHandler);

const PORT = process.env.PORT || 3000;
app.listen(Number(PORT), '0.0.0.0', () => {
  console.log(`MoreTime API running on port ${PORT}`);
});

export default app;
