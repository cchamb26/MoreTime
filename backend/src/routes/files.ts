import { Router, Request, Response, NextFunction } from 'express';
import multer from 'multer';
import path from 'node:path';
import fs from 'node:fs/promises';
import { getSupabase } from '../utils/supabase.js';
import { authGuard } from '../middleware/auth.js';
import { NotFoundError, ValidationError } from '../utils/errors.js';
import { parseFile } from '../services/fileParser.js';
import { extractTasksFromContent, detectDocumentType, breakdownAssignment } from '../services/ai.js';
import { toCamel } from '../utils/transform.js';

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
  limits: { fileSize: 10 * 1024 * 1024 },
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
    const supabase = getSupabase();
    const uploads = [];

    for (const file of files) {
      const { data, error } = await supabase
        .from('file_uploads')
        .insert({
          user_id: req.user!.userId,
          course_id: courseId,
          original_name: file.originalname,
          storage_path: file.path,
          mime_type: file.mimetype,
          file_size: file.size,
          parse_status: 'pending',
        })
        .select()
        .single();

      if (error) throw error;
      uploads.push(toCamel(data));

      parseFileInBackground(data.id, file.path, file.mimetype);
    }

    res.status(201).json(uploads);
  } catch (err) {
    next(err);
  }
});

async function parseFileInBackground(fileId: string, filePath: string, mimeType: string) {
  const supabase = getSupabase();
  try {
    await supabase
      .from('file_uploads')
      .update({ parse_status: 'parsing' })
      .eq('id', fileId);

    const content = await parseFile(filePath, mimeType);

    await supabase
      .from('file_uploads')
      .update({
        parsed_content: content,
        parse_status: 'completed',
        parsed_at: new Date().toISOString(),
      })
      .eq('id', fileId);
  } catch (err) {
    console.error(`Failed to parse file ${fileId}:`, err);
    await supabase
      .from('file_uploads')
      .update({ parse_status: 'failed' })
      .eq('id', fileId);
  }
}

router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const supabase = getSupabase();

    const { data, error } = await supabase
      .from('file_uploads')
      .select('*')
      .eq('id', id)
      .eq('user_id', req.user!.userId)
      .single();

    if (error || !data) throw new NotFoundError('FileUpload', id);
    res.json(toCamel(data));
  } catch (err) {
    next(err);
  }
});

router.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const supabase = getSupabase();

    const { data, error } = await supabase
      .from('file_uploads')
      .select('id, original_name, mime_type, file_size, parse_status, parsed_at, course_id, created_at')
      .eq('user_id', req.user!.userId)
      .order('created_at', { ascending: false });

    if (error) throw error;
    res.json((data ?? []).map((f: unknown) => toCamel(f)));
  } catch (err) {
    next(err);
  }
});

router.post('/:id/extract-tasks', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const supabase = getSupabase();

    const { data: file, error } = await supabase
      .from('file_uploads')
      .select('*')
      .eq('id', id)
      .eq('user_id', req.user!.userId)
      .single();

    if (error || !file) throw new NotFoundError('FileUpload', id);
    if (!file.parsed_content) throw new ValidationError('File has not been parsed yet');

    const docType = await detectDocumentType(file.parsed_content);
    const dueDate = req.body.dueDate ?? null;

    const extracted = docType === 'assignment'
      ? await breakdownAssignment(file.parsed_content, dueDate)
      : await extractTasksFromContent(file.parsed_content, file.course_id);

    const tasks = [];
    for (const item of extracted) {
      const { data: task, error: taskError } = await supabase
        .from('tasks')
        .insert({
          user_id: req.user!.userId,
          course_id: file.course_id,
          title: item.title,
          description: item.description || '',
          due_date: item.dueDate ?? null,
          estimated_hours: item.estimatedHours || 2,
          priority: item.priority || 2,
        })
        .select('*, courses:course_id(id, name, color)')
        .single();

      if (!taskError && task) {
        const { courses, user_id, ...rest } = task as Record<string, unknown>;
        tasks.push({ ...toCamel(rest), course: courses ? toCamel(courses) : null });
      }
    }

    res.status(201).json({ extractedCount: tasks.length, tasks, documentType: docType });
  } catch (err) {
    next(err);
  }
});

export default router;
