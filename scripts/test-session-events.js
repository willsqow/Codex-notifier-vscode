"use strict";

const assert = require("assert");
const {
  isHistoricalSessionCompletion,
  isHistoricalSessionRequest,
  parseRequestUserInputLine,
  cleanUserPrompt,
  parseUserMessageLine,
  parseTaskCompleteLine,
  parseTimestampMs
} = require("../session-events");

function completionLine(turnId, completedAt) {
  return JSON.stringify({
    timestamp: "2026-07-30T23:05:23.159Z",
    type: "event_msg",
    payload: {
      type: "task_complete",
      turn_id: turnId,
      completed_at: completedAt
    }
  });
}

function requestUserInputLine(turnId, callId, requestedAt, questions = [{
  header: "choice",
  question: "Pick one",
  options: ["One", "Two"]
}]) {
  return JSON.stringify({
    timestamp: requestedAt,
    type: "response_item",
    payload: {
      type: "function_call",
      id: "fc_test",
      name: "request_user_input",
      arguments: JSON.stringify({ questions }),
      call_id: callId,
      internal_chat_message_metadata_passthrough: {
        turn_id: turnId
      }
    }
  });
}

const forkedSession = {
  forkedFromId: "parent-session",
  createdAtMs: Date.parse("2026-07-30T23:05:22.986Z")
};
const watcherStartedAtMs = Date.parse("2026-07-30T23:00:00.000Z");

const inherited = parseTaskCompleteLine(
  completionLine("old-turn", 1785452598)
);
assert.strictEqual(inherited.turnId, "old-turn");
assert.strictEqual(
  isHistoricalSessionCompletion(inherited, forkedSession, watcherStartedAtMs),
  true,
  "a completion copied from before the fork must be ignored"
);

const newCompletion = parseTaskCompleteLine(
  completionLine("new-turn", 1785452820)
);
assert.strictEqual(
  isHistoricalSessionCompletion(newCompletion, forkedSession, watcherStartedAtMs),
  false,
  "a completion produced after the fork must notify"
);

const resumedSession = {
  forkedFromId: "",
  createdAtMs: Date.parse("2026-07-30T16:30:19.903Z")
};
const oldResumedCompletion = parseTaskCompleteLine(
  completionLine("old-resumed-turn", 1785429316)
);
assert.strictEqual(
  isHistoricalSessionCompletion(oldResumedCompletion, resumedSession, watcherStartedAtMs),
  true,
  "old completions from a resumed top-level chat must be ignored"
);
assert.strictEqual(
  isHistoricalSessionCompletion(newCompletion, resumedSession, watcherStartedAtMs),
  false,
  "a new completion from a resumed top-level chat must notify"
);

const request = parseRequestUserInputLine(
  requestUserInputLine("prompt-turn", "call_prompt", "2026-07-30T23:05:24.159Z")
);
assert.strictEqual(request.turnId, "prompt-turn");
assert.strictEqual(request.callId, "call_prompt");
assert.strictEqual(
  isHistoricalSessionRequest(request, forkedSession, watcherStartedAtMs),
  false,
  "a new request_user_input prompt must notify"
);

const historicalRequest = parseRequestUserInputLine(
  requestUserInputLine("old-prompt-turn", "call_old_prompt", "2026-07-30T22:59:59.159Z")
);
assert.strictEqual(
  isHistoricalSessionRequest(historicalRequest, forkedSession, watcherStartedAtMs),
  true,
  "a pre-watch request_user_input prompt must be ignored"
);

assert.strictEqual(
  parseRequestUserInputLine(requestUserInputLine(
    "empty-prompt-turn",
    "call_empty_prompt",
    "2026-07-30T23:05:24.159Z",
    []
  )),
  undefined,
  "an empty request_user_input payload must not notify"
);

const objectArgumentsLine = JSON.parse(requestUserInputLine(
  "object-prompt-turn",
  "call_object_prompt",
  "2026-07-30T23:05:24.159Z"
));
objectArgumentsLine.payload.arguments = {
  questions: [{ question: "Pick one" }]
};
assert.strictEqual(
  parseRequestUserInputLine(JSON.stringify(objectArgumentsLine)).turnId,
  "object-prompt-turn",
  "an object-form arguments payload must remain supported"
);

const malformedQuestionLine = JSON.parse(requestUserInputLine(
  "malformed-prompt-turn",
  "call_malformed_prompt",
  "2026-07-30T23:05:24.159Z"
));
malformedQuestionLine.payload.arguments = JSON.stringify({ questions: [{ header: "missing-text" }] });
assert.strictEqual(
  parseRequestUserInputLine(JSON.stringify(malformedQuestionLine)),
  undefined,
  "a request without visible question text must not notify"
);

assert.strictEqual(
  isHistoricalSessionCompletion({ turnId: "missing-time" }, forkedSession, watcherStartedAtMs),
  true,
  "an undated completion in the initial session snapshot must be ignored"
);
assert.strictEqual(
  isHistoricalSessionCompletion({ turnId: "later-missing-time" }, forkedSession, undefined),
  false,
  "an undated completion appended later must remain eligible"
);

assert.strictEqual(parseTimestampMs("2026-07-30T23:05:22.986Z"), forkedSession.createdAtMs);
assert.strictEqual(
  parseUserMessageLine(JSON.stringify({
    type: "event_msg",
    payload: { type: "user_message", message: "  test prompt  " }
  })),
  "test prompt"
);
assert.strictEqual(
  parseUserMessageLine(JSON.stringify({
    type: "response_item",
    payload: {
      type: "message",
      role: "user",
      content: [{ type: "input_text", text: "response prompt" }]
    }
  })),
  "response prompt"
);
assert.strictEqual(
  cleanUserPrompt("# Context from my IDE setup:\n## Active file: extension.js\n## My request:\nrebuild"),
  "rebuild"
);
assert.strictEqual(parseTimestampMs(1785452722), 1785452722000);
assert.strictEqual(parseTaskCompleteLine('{"type":"event_msg","payload":{"type":"token_count"}}'), undefined);
assert.strictEqual(
  parseRequestUserInputLine('{"type":"response_item","payload":{"type":"function_call","name":"shell_command"}}'),
  undefined
);

console.log("Session event tests passed.");
