import { Router, Request, Response, NextFunction } from 'express';
import multer from 'multer';
import path from 'node:path';
import fs from 'node:fs/promises';
import { prisma } from '../utils/db.js';
import { authGuard } from '../middleware/auth.js';
import { NotFoundError, ValidationError } from '../utils/errors.js';
import { parseFile } from '../services/fileParser.js';
import { extractTasksFromContent } from '../services/ai.js';

const UPLOAD_DIR = path.join(process.cwd(), 'uploads');

const storage = multer.diskStorage({
  destination: async (_req, _file, cb) => {
    await fs.mkdir(UPLOAD_DIR, { recursive: true });
    cb(null, UPLOAD_DIR);
  },
  filename: (_req, file, cb) => {
    const unique = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    cb(null, `${unique}${path.extname(file.originalname)}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (_req, file, cb) => {
    const allowed = [
      'application/pdf',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'text/plain',
      'image/png',
      'image/jpeg',
      'image/jpg',
    ];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new ValidationError(`Unsupported file type: ${file.mimetype}`));
    }
  },
});

const router = Router();
router.use(authGuard);

router.post('/upload', upload.array('files', 10), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const files = req.files as Express.Multer.File[];
    if (!files?.length) throw new ValidationError('No files uploaded');

    const courseId = req.body.courseId || null;
    const uploads = [];

    for (const file of files) {
      const record = await prisma.fileUpload.create({
        data: {
          userId: req.user!.userId,
          courseId,
          originalName: file.originalname,
          storagePath: file.path,
          mimeType: file.mimetype,
          fileSize: file.size,
          parseStatus: 'pending',
        },
      });
      uploads.push(record);

      // Parse asynchronously
      parseFileInBackground(record.id, file.path, file.mimetype);
    }

    res.status(201).json(uploads);
  } catch (err) {
    next(err);
  }
});

async function parseFileInBackground(fileId: string, filePath: string, mimeType: string) {
  try {
    await prisma.fileUpload.update({
      where: { id: fileId },
      data: { parseStatus: 'parsing' },
    });

    const content = await parseFile(filePath, mimeType);

    await prisma.fileUpload.update({
      where: { id: fileId },
      data: {
        parsedContent: content,
        parseStatus: 'completed',
        parsedAt: new Date(),
      },
    });
  } catch (err) {
    console.error(`Failed to parse file ${fileId}:`, err);
    await prisma.fileUpload.update({
      where: { id: fileId },
      data: { parseStatus: 'failed' },
    });
  }
}

router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const file = await prisma.fileUpload.findFirst({
      where: { id, userId: req.user!.userId },
    });
    if (!file) throw new NotFoundError('FileUpload', id);
    res.json(file);
  } catch (err) {
    next(err);
  }
});

router.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const files = await prisma.fileUpload.findMany({
      where: { userId: req.user!.userId },
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        originalName: true,
        mimeType: true,
        fileSize: true,
        parseStatus: true,
        parsedAt: true,
        courseId: true,
        createdAt: true,
      },
    });
    res.json(files);
  } catch (err) {
    next(err);
  }
});

router.post('/:id/extract-tasks', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const file = await prisma.fileUpload.findFirst({
      where: { id, userId: req.user!.userId },
    });
    if (!file) throw new NotFoundError('FileUpload', id);
    if (!file.parsedContent) throw new ValidationError('File has not been parsed yet');

    const extracted = await extractTasksFromContent(file.parsedContent, file.courseId);

    // Create tasks from extracted data
    const tasks = [];
    for (const item of extracted) {
      const task = await prisma.task.create({
        data: {
          userId: req.user!.userId,
          courseId: file.courseId,
          title: item.title,
          description: item.description || '',
          dueDate: item.dueDate ? new Date(item.dueDate) : null,
          estimatedHours: item.estimatedHours || 2,
          priority: item.priority || 2,
        },
        include: { course: { select: { id: true, name: true, color: true } } },
      });
      tasks.push(task);
    }

    res.status(201).json({ extractedCount: tasks.length, tasks });
  } catch (err) {
    next(err);
  }
});

export default router;
