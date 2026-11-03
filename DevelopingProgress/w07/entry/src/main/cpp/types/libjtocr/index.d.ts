export interface NativeWord {
  text: string;
  x: number;
  y: number;
  width: number;
  height: number;
  confidence: number;
}
export interface NativeLine extends NativeWord { words: NativeWord[]; }
export const recognize: (rgba: ArrayBuffer, width: number, height: number, tessdataDirectory: string) => Promise<NativeLine[]>;
