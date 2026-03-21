import * as sdk from 'microsoft-cognitiveservices-speech-sdk';
import fs from 'node:fs/promises';
import { getEnv } from '../utils/env.js';

export async function transcribeAudio(filePath: string): Promise<string> {
  const env = getEnv();

  if (!env.AZURE_SPEECH_KEY) {
    throw new Error('Azure Speech Services not configured (AZURE_SPEECH_KEY missing)');
  }

  const speechConfig = sdk.SpeechConfig.fromSubscription(env.AZURE_SPEECH_KEY, env.AZURE_SPEECH_REGION);
  speechConfig.speechRecognitionLanguage = 'en-US';

  const audioConfig = sdk.AudioConfig.fromWavFileInput(await fs.readFile(filePath));
  const recognizer = new sdk.SpeechRecognizer(speechConfig, audioConfig);

  return new Promise<string>((resolve, reject) => {
    let fullText = '';

    recognizer.recognized = (_sender, event) => {
      if (event.result.reason === sdk.ResultReason.RecognizedSpeech) {
        fullText += event.result.text + ' ';
      }
    };

    recognizer.canceled = (_sender, event) => {
      if (event.reason === sdk.CancellationReason.Error) {
        reject(new Error(`Speech recognition error: ${event.errorDetails}`));
      }
      recognizer.stopContinuousRecognitionAsync();
    };

    recognizer.sessionStopped = () => {
      recognizer.stopContinuousRecognitionAsync();
      resolve(fullText.trim());
    };

    recognizer.startContinuousRecognitionAsync(
      () => {},
      (err) => reject(new Error(`Failed to start recognition: ${err}`)),
    );
  });
}
