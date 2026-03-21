import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { errorHandler } from './middleware/errorHandler.js';
import { getSupabase } from './utils/supabase.js';

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

// Dev bypass: create a dev auth user so the profile trigger fires
if (process.env.DEV_BYPASS_AUTH === 'true') {
  const DEV_ID = '00000000-0000-0000-0000-000000000000';
  const supabase = getSupabase();
  supabase.auth.admin
    .createUser({
      id: DEV_ID,
      email: 'dev@moretime.local',
      password: 'devbypass123',
      email_confirm: true,
      user_metadata: { name: 'Dev User', timezone: 'America/New_York' },
    })
    .then(({ error }) => {
      if (error && !error.message.includes('already')) {
        console.error('Failed to seed dev user:', error.message);
      } else {
        console.log('Dev bypass auth enabled — dev user seeded');
      }
    });
}

// Error handler (must be last)
app.use(errorHandler);

const PORT = process.env.PORT || 3000;
app.listen(Number(PORT), '0.0.0.0', () => {
  console.log(`MoreTime API running on port ${PORT}`);
});

export default app;
