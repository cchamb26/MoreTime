import fs from 'node:fs/promises';
import path from 'node:path';
import { getEnv } from '../utils/env.js';

interface TranscriptionResponse {
  text: string;
}

export async function transcribeAudio(filePath: string): Promise<string> {
  const env = getEnv();

  const deploymentName = 'gpt-4o-transcribe-diarize';
  const url = `${env.AZURE_OPENAI_ENDPOINT}openai/deployments/${deploymentName}/audio/transcriptions?api-version=2025-03-01-preview`;

  const fileBuffer = await fs.readFile(filePath);
  const fileName = path.basename(filePath);

  const formData = new FormData();
  formData.append('model', deploymentName);
  formData.append('file', new Blob([fileBuffer]), fileName);

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'api-key': env.AZURE_OPENAI_API_KEY,
    },
    body: formData,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Transcription failed (${response.status}): ${errorBody}`);
  }

  const result = (await response.json()) as TranscriptionResponse;
  return result.text;
}
