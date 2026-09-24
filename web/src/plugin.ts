import { WorkerRuntime } from '@language-playground/ide/transport';
import type { EditorLanguage, Example, LanguagePlugin } from '@language-playground/ide/api';
import { createAnalysisService } from './service';

const programs = [
  ['twice', 'Functions as values', 'Apply a function twice.',
    '// Functions can accept and return other functions.\nlet twice = (f: Nat → Nat, x: Nat) ⇒ f (f x)\nlet increment = (n: Nat) ⇒ n + 1\ntwice(increment, 40)'],
  ['factorial', 'Recursive factorial', 'Define a recursive function with a typed parameter.',
    'def factorial (n: Nat) =\n  if n == 0 then 1 else n * factorial (n - 1)\nlet answer = factorial 5\nanswer'],
  ['scope', 'Lexical scope', 'Closures remember the environment where they were created.',
    'let x = 10\nlet addX = (y: Nat) ⇒ x + y\nlet x = 99\naddX 2'],
  ['booleans', 'Choosing a function', 'Both branches have the same function type.',
    'let choose = (b: Bool) ⇒\n  if b then (n: Nat) ⇒ n * n else (n: Nat) ⇒ n + 1 in\nchoose(3 < 4, 6)'],
  ['naturals', 'Large natural numbers', 'Exact arithmetic and subtraction truncated at zero.',
    '// Natural numbers have arbitrary precision.\nlet big = 99999999999999999999999999 in\nbig * big + (3 - 8)'],
  ['error', 'A type error', 'The checker rejects an argument with the wrong type.',
    'let increment = (n: Nat) ⇒ n + 1 in\nincrement(false)'],
] as const;

export const examples: Example[] = programs.map(([id, title, description, text]) => ({
  id, title, description, files: [{ path: 'main.stlc', text }], entryPath: 'main.stlc',
}));

export function createRuntime() {
  return new WorkerRuntime(() => new Worker(new URL('./runtime.worker.ts', import.meta.url), { type: 'module' }));
}

export const plugin: LanguagePlugin = {
  definition: {
    id: 'lean-stlc', name: 'STLC', extension: '.stlc',
    defaultFilePath: 'main.stlc', defaultEntryPoint: '', examples,
  },
  createRuntime,
  createLanguageService: () => createAnalysisService(createRuntime),
};

export const editor: EditorLanguage = {
  install(api, language) {
    if (!api.languages.getLanguages().some((item) => item.id === language.id)) {
      api.languages.register({ id: language.id, extensions: ['.stlc'] });
    }
    const configuration = api.languages.setLanguageConfiguration(language.id, {
      comments: { lineComment: '//', blockComment: ['/*', '*/'] },
      brackets: [['(', ')'], ['{', '}']],
      autoClosingPairs: [{ open: '(', close: ')' }, { open: '{', close: '}' }],
    });
    const tokens = api.languages.setMonarchTokensProvider(language.id, {
      keywords: ['let', 'def', 'fix', 'in', 'if', 'then', 'else', 'true', 'false'],
      tokenizer: {
        root: [
          [/\/\*/, 'comment', '@comment'], [/\/\/.*$/, 'comment'],
          [/\b(Unit|Nat|Bool)\b/, 'type'],
          [/[a-zA-Z_\u0370-\u03ff][a-zA-Z_0-9'\u0370-\u03ff]*/, { cases: { '@keywords': 'keyword', '@default': 'identifier' } }],
          [/\d+/, 'number'], [/⇒|→|=>|->|==|[+*<−=:-]/, 'operator'], [/[(){}]/, '@brackets'], [/,/, 'delimiter'],
        ],
        comment: [[/\/\*/, 'comment', '@push'], [/\*\//, 'comment', '@pop'], [/[^/*]+|[/*]/, 'comment']],
      },
    });
    const registrations = [configuration, tokens];
    // Installation precedes editor creation and model attachment.
    registrations.push(api.editor.onDidCreateEditor((instance) => {
      const configureUnicode = () => {
        if (instance.getModel()?.getLanguageId() !== language.id) return;
        const current = instance.getOption(api.editor.EditorOption.unicodeHighlighting);
        instance.updateOptions({
          unicodeHighlight: { allowedCharacters: { ...current.allowedCharacters, '−': true } },
        });
      };
      registrations.push(
        instance.onDidChangeModel(configureUnicode),
        instance.onDidChangeModelLanguage(configureUnicode),
      );
      configureUnicode();
    }));
    return { dispose() { for (const registration of registrations) registration.dispose(); } };
  },
};
