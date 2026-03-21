import fs from 'node:fs/promises';
import path from 'node:path';

export async function parseFile(filePath: string, mimeType: string): Promise<string> {
  switch (mimeType) {
    case 'text/plain':
      return parseTxt(filePath);
    case 'application/pdf':
      return parsePdf(filePath);
    case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
      return parseDocx(filePath);
    case 'image/png':
    case 'image/jpeg':
    case 'image/jpg':
      return parseImage(filePath);
    default:
      throw new Error(`Unsupported mime type: ${mimeType}`);
  }
}

async function parseTxt(filePath: string): Promise<string> {
  return fs.readFile(filePath, 'utf-8');
}

async function parsePdf(filePath: string): Promise<string> {
  const pdfParse = (await import('pdf-parse')).default;
  const buffer = await fs.readFile(filePath);
  const data = await pdfParse(buffer);

  // Fall back to OCR if very little text extracted
  if (data.text.trim().length < 100) {
    console.log(`PDF ${path.basename(filePath)} yielded little text, attempting OCR via AI vision`);
    return parseImage(filePath);
  }

  return data.text;
}

async function parseDocx(filePath: string): Promise<string> {
  const mammoth = await import('mammoth');
  const buffer = await fs.readFile(filePath);
  const result = await mammoth.extractRawText({ buffer });
  return result.value;
}

async function parseImage(filePath: string): Promise<string> {
  // Use GPT-4o vision to extract text from images
  const { getOpenAIClient, getDeploymentName } = await import('../utils/azure-openai.js');
  const client = getOpenAIClient();

  const buffer = await fs.readFile(filePath);
  const base64 = buffer.toString('base64');
  const ext = path.extname(filePath).toLowerCase();
  const mimeMap: Record<string, string> = {
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.pdf': 'application/pdf',
  };

  const response = await client.chat.completions.create({
    model: getDeploymentName(),
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'text',
            text: 'Extract all text from this image. Preserve the structure and formatting as much as possible. If this is a syllabus or academic document, capture all dates, assignments, and course details.',
          },
          {
            type: 'image_url',
            image_url: {
              url: `data:${mimeMap[ext] || 'image/png'};base64,${base64}`,
            },
          },
        ],
      },
    ],
    max_tokens: 4000,
  });

  return response.choices[0]?.message?.content ?? '';
}
