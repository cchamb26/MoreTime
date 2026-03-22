import { z } from 'zod';

const envSchema = z.object({
  SUPABASE_URL: z.string(),
  SUPABASE_SERVICE_ROLE_KEY: z.string(),
  AZURE_OPENAI_ENDPOINT: z.string(),
  AZURE_OPENAI_API_KEY: z.string(),
  AZURE_OPENAI_DEPLOYMENT_NAME: z.string().default('gpt-4o'),
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
