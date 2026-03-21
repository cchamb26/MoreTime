import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { authGuard } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { handleChatMessage } from '../services/chat.js';

const router = Router();
router.use(authGuard);

const chatSchema = z.object({
  message: z.string().min(1).max(5000),
  sessionId: z.string().optional(),
});

router.post(
  '/message',
  validate(chatSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { message, sessionId } = req.body;
      const result = await handleChatMessage(req.user!.userId, message, sessionId);
      res.json(result);
    } catch (err) {
      next(err);
    }
  },
);

export default router;
