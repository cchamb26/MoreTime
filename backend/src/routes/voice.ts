import { Router, Request, Response, NextFunction } from 'express';
import multer from 'multer';
import path from 'node:path';
import fs from 'node:fs/promises';
import { authGuard } from '../middleware/auth.js';
import { ValidationError } from '../utils/errors.js';
import { transcribeAudio } from '../services/voice.js';
import { handleChatMessage } from '../services/chat.js';

const VOICE_DIR = path.join(process.cwd(), 'uploads', 'voice');

const storage = multer.diskStorage({
  destination: async (_req, _file, cb) => {
    await fs.mkdir(VOICE_DIR, { recursive: true });
    cb(null, VOICE_DIR);
  },
  filename: (_req, file, cb) => {
    const unique = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    cb(null, `${unique}${path.extname(file.originalname)}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 25 * 1024 * 1024 }, // 25MB for audio
  fileFilter: (_req, file, cb) => {
    const allowed = ['audio/m4a', 'audio/wav', 'audio/webm', 'audio/mp4', 'audio/mpeg', 'audio/x-m4a'];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new ValidationError(`Unsupported audio format: ${file.mimetype}`));
    }
  },
});

const router = Router();
router.use(authGuard);

router.post('/transcribe', upload.single('audio'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.file) throw new ValidationError('No audio file uploaded');

    const text = await transcribeAudio(req.file.path);

    // Clean up audio file after transcription
    await fs.unlink(req.file.path).catch(() => {});

    res.json({ text });
  } catch (err) {
    next(err);
  }
});

router.post('/chat', upload.single('audio'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.file) throw new ValidationError('No audio file uploaded');

    const text = await transcribeAudio(req.file.path);
    await fs.unlink(req.file.path).catch(() => {});

    const sessionId = req.body.sessionId;
    const result = await handleChatMessage(req.user!.userId, text, sessionId);

    res.json({ transcription: text, ...result });
  } catch (err) {
    next(err);
  }
});

export default router;
