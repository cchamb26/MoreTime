import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { authGuard } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { handleChatMessage } from '../services/chat.js';

const router = Router();
router.use(authGuard);

const chatSchema = z
  .object({
    message: z.string().max(5000).default(''),
    sessionId: z.string().optional(),
    fileIds: z.array(z.string().uuid()).max(5).optional(),
  })
  .superRefine((data, ctx) => {
    const text = data.message.trim();
    const hasFiles = (data.fileIds?.length ?? 0) > 0;
    if (!text && !hasFiles) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'Provide a message and/or at least one fileId',
      });
    }
  });

router.post(
  '/message',
  validate(chatSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { message, sessionId, fileIds } = req.body as z.infer<typeof chatSchema>;
      const result = await handleChatMessage(req.user!.userId, message, sessionId, fileIds);
      res.json(result);
    } catch (err) {
      next(err);
    }
  },
);

export default router;
