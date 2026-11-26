# 0.8.2 AI model selection and reasoning strength verification

Design: searchable native provider catalogue and independent animated strength selector; saved selection scoped to endpoint/model. The interface retains manual model IDs. Only explicit model-directory queries send authentication, never article text or history. Service default omits reasoning_effort. Unknown capabilities use service default until the provider supplies supported levels.

- `check-research-ai.sh` passed synthetic GET model directory URL/HTTP method/no body, authentication and endpoint-scoped credentials, malformed/duplicate entries, cancellation and stale result isolation, supported model capabilities and explicit `reasoning_effort`, non-supported omission, persistence and conversation history checks.
- `check-research-integration.sh` passed document-scoped notes/chats and reader lifecycle.
- `check-research-notes.sh` passed notebook persistence and selection cases.
- `preview-ai-controls.sh` rendered the native settings, searchable model catalogue, reasoning options and sidebar at high/extra-high using a synthetic API response and injected credential source. Verified visual hierarchy, bounded scroll lists, current selection marks, and full save button. No real key or live API calls were used.
- Review identified unsaved draft directory persisting after an address change; fixed by invalidating the prior endpoint before clearing unsaved input, then repeated preview and tests.
- Release optimized arm64 macOS 13+ binary compiled, signed ad hoc. ZIP extracted, version 0.8.2 and full bundle signature verified; previous version runtime reused.

Official API semantics: OpenAI https://developers.openai.com/api/docs/guides/reasoning ; model directory https://developers.openai.com/api/reference/python/resources/models/methods/list ; DeepSeek https://api-docs.deepseek.com/api/list-models/ and https://api-docs.deepseek.com/api/create-chat-completion/. Actual model availability depends on user account and service. Higher effort may cost more and take longer. No live provider usage billed in tests.
