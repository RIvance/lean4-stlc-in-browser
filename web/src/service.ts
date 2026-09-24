import type { AnalysisUpdate, LanguageRuntime, LanguageService, ServiceLog, SourceDocument } from '@language-playground/ide/api';

/** Analysis runs the same Lean parser/checker in an independently cancellable worker. */
export function createAnalysisService(createRuntime: () => LanguageRuntime): LanguageService {
  const updates = new Set<(update: AnalysisUpdate) => void>();
  const failures = new Set<(error: Error) => void>();
  const logs = new Set<(log: ServiceLog) => void>();
  const pending = new Map<string, { version: number; timer: ReturnType<typeof setTimeout>; abort: AbortController }>();
  let disposed = false;

  function close(uri: string) {
    const previous = pending.get(uri);
    if (!previous) return;
    clearTimeout(previous.timer);
    previous.abort.abort();
    pending.delete(uri);
  }

  function synchronize(document: SourceDocument) {
    if (disposed || (pending.get(document.uri)?.version ?? -1) >= document.version) return;
    close(document.uri);
    const abort = new AbortController();
    const timer = setTimeout(async () => {
      try {
        const result = await createRuntime().execute({
          documents: [document], entryDocumentUri: document.uri, entryPoint: 'check', stdin: '',
        }, () => {}, abort.signal);
        if (disposed || abort.signal.aborted) return;
        for (const listener of updates) listener({ uri: document.uri, version: document.version, diagnostics: result.diagnostics });
      } catch (error) {
        if (disposed || abort.signal.aborted) return;
        for (const listener of failures) listener(error instanceof Error ? error : new Error(String(error)));
      }
    }, 400);
    pending.set(document.uri, { version: document.version, timer, abort });
  }

  return {
    capabilities: {}, start: async () => {}, synchronize, close,
    onDiagnostics(listener) { updates.add(listener); return () => { updates.delete(listener); }; },
    onLog(listener) { logs.add(listener); return () => { logs.delete(listener); }; },
    onFailure(listener) { failures.add(listener); return () => { failures.delete(listener); }; },
    dispose() {
      disposed = true;
      for (const uri of pending.keys()) close(uri);
      updates.clear(); failures.clear(); logs.clear();
    },
  };
}
