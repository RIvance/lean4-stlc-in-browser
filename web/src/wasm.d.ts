declare module '*stlc.mjs' {
  interface LeanModule {
    _stlc_init(): number;
    _free(pointer: number): void;
    ccall(name: string, result: 'number', types: string[], args: (string | number)[]): number;
    UTF8ToString(pointer: number): string;
  }
  export default function createModule(options?: {
    locateFile?: (path: string) => string;
    print?: (text: string) => void;
    printErr?: (text: string) => void;
  }): Promise<LeanModule>;
}
