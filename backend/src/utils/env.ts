import { z } from 'zod';

const envSchema = z.object({
  DATABASE_URL: z.string(),
  JWT_SECRET: z.string(),
  JWT_REFRESH_SECRET: z.string(),
  AZURE_OPENAI_ENDPOINT: z.string(),
  AZURE_OPENAI_API_KEY: z.string(),
  AZURE_OPENAI_DEPLOYMENT_NAME: z.string().default('gpt-4o'),
  AZURE_SPEECH_KEY: z.string().optional(),
  AZURE_SPEECH_REGION: z.string().default('eastus'),
  PORT: z.string().default('3000').transform(Number),
});

export type Env = z.infer<typeof envSchema>;

let _env: Env | null = null;

export function getEnv(): Env {
  if (!_env) {
    const result = envSchema.safeParse(process.env);
    if (!result.success) {
      console.error('Invalid environment variables:', result.error.flatten().fieldErrors);
      process.exit(1);
    }
    _env = result.data;
  }
  return _env;
}
