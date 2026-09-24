import { serveExecution } from '@language-playground/ide/transport';
import type { ExecutionResult, Range } from '@language-playground/ide/api';
import createModule from '../generated/stlc.mjs';
import wasmUrl from '../generated/stlc.wasm?url';

type Response =
  | { status: 'success'; type: string; value: string | null; term: string; steps: number }
  | { status: 'error'; diagnostic: { phase: string; message: string; range: Range } };

// Instantiation is lazy so a failure is returned through the playground's RPC.
let modulePromise: ReturnType<typeof createModule> | undefined;
function loadModule() {
  return (modulePromise ??= createModule({ locateFile: () => wasmUrl }).then((module) => {
    if (module._stlc_init() !== 0) throw new Error('Lean runtime initialization failed.');
    return module;
  }));
}

serveExecution(self, {
  async execute(input): Promise<ExecutionResult> {
    const document = input.documents.find((candidate) => candidate.uri === input.entryDocumentUri);
    if (!document) throw new Error('The entry document is missing.');
    const module = await loadModule();
    const pointer = module.ccall('stlc_request', 'number', ['string', 'number', 'number', 'number'], [
      document.text,
      new TextEncoder().encode(document.text).length,
      100_000,
      input.entryPoint === 'check' ? 1 : 0,
    ]);
    if (!pointer) throw new Error('The Lean runtime ran out of memory.');
    let response: Response;
    try {
      response = JSON.parse(module.UTF8ToString(pointer)) as Response;
    } finally {
      module._free(pointer);
    }
    if (response.status === 'error') {
      const diagnostic = response.diagnostic;
      return {
        status: 'error',
        diagnostics: [{
          message: `${diagnostic.phase}: ${diagnostic.message}`,
          severity: 'error',
          source: 'Lean STLC',
          location: { uri: document.uri, range: diagnostic.range },
        }],
        artifacts: [],
      };
    }
    return {
      status: 'success',
      value: `${response.value ?? '✓'} : ${response.type}`,
      diagnostics: [],
      artifacts: [
        { name: 'Parsed expression', mediaType: 'text/plain', content: response.term },
        { name: 'Evaluation', mediaType: 'text/plain', content: `${response.steps} machine steps\nType: ${response.type}` },
      ],
    };
  },
});
