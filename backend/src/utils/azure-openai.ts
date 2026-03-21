import { AzureOpenAI } from 'openai';
import { getEnv } from './env.js';

let _client: AzureOpenAI | null = null;

export function getOpenAIClient(): AzureOpenAI {
  if (!_client) {
    const env = getEnv();
    _client = new AzureOpenAI({
      endpoint: env.AZURE_OPENAI_ENDPOINT,
      apiKey: env.AZURE_OPENAI_API_KEY,
      apiVersion: '2024-10-21',
      deployment: env.AZURE_OPENAI_DEPLOYMENT_NAME,
    });
  }
  return _client;
}

export function getDeploymentName(): string {
  return getEnv().AZURE_OPENAI_DEPLOYMENT_NAME;
}
