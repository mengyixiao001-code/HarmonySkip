declare const hdc: {
  start(tempDir: string): void;
  run(command: string, tempDir: string, target?: string): Promise<string>;
};
export default hdc;
