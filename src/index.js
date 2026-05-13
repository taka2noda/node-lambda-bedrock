'use strict';

// dd-trace must be initialized before other imports (per Datadog docs)
const tracer = require('dd-trace').init();

const { datadog } = require('datadog-lambda-js');
const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime');

const bedrockClient = new BedrockRuntimeClient({
  region: process.env.AWS_REGION || 'us-west-2',
});

const myHandler = async (event) => {
  const userId = event.userId || event.user_id || 'anonymous';
  const prompt = event.prompt || 'Say hello in one sentence.';

  // APM Server-Side Custom Instrumentation: tag current span with user ID
  const span = tracer.scope().active();
  if (span) {
    span.setTag('usr.id', userId);
  }

  const modelId = process.env.BEDROCK_MODEL_ID || 'us.anthropic.claude-haiku-4-5-20251001-v1:0';

  const command = new InvokeModelCommand({
    modelId,
    body: JSON.stringify({
      anthropic_version: 'bedrock-2023-05-31',
      max_tokens: 1024,
      messages: [{ role: 'user', content: prompt }],
    }),
    contentType: 'application/json',
    accept: 'application/json',
  });

  const response = await bedrockClient.send(command);
  const responseBody = JSON.parse(new TextDecoder().decode(response.body));

  return {
    statusCode: 200,
    body: JSON.stringify({
      userId,
      message: responseBody.content[0].text,
    }),
  };
};

module.exports.handler = datadog(myHandler);
