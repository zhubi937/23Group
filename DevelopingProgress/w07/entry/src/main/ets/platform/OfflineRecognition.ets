import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import nativeOcr, { NativeLine, NativeWord } from 'libjtocr.so';
import { Box, OcrLine } from '../domain/Models';

export class OfflineRecognition {
  private async models(context: common.UIAbilityContext): Promise<string> {
    const directory = context.filesDir + '/tessdata';
    if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
    const names: string[] = ['chi_sim.traineddata', 'eng.traineddata'];
    const sizes: number[] = [2469156, 4113088];
    for (let i = 0; i < names.length; i++) {
      const path = directory + '/' + names[i];
      if (fs.accessSync(path) && fs.statSync(path).size === sizes[i]) { continue; }
      const data = await context.resourceManager.getRawFileContent('tessdata/' + names[i]);
      if (data.byteLength !== sizes[i]) { throw new Error('离线模型资源不完整，请重新安装应用'); }
      const temporary = path + '.tmp';
      const file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try { await fs.write(file.fd, data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength)); }
      finally { fs.closeSync(file); }
      fs.renameSync(temporary, path);
    }
    return directory;
  }
  async run(pixels: image.PixelMap, originalWidth: number, originalHeight: number, context: common.UIAbilityContext): Promise<OcrLine[]> {
    const directory = await this.models(context);
    const info = await pixels.getImageInfo();
    const data = new ArrayBuffer(pixels.getPixelBytesNumber());
    await pixels.readPixelsToBuffer(data);
    const result: NativeLine[] = await nativeOcr.recognize(data, info.size.width, info.size.height, directory);
    const sx = originalWidth / info.size.width; const sy = originalHeight / info.size.height;
    return result.filter((l: NativeLine) => l.text.trim().length > 0).map((l: NativeLine, i: number) => {
      const line = new OcrLine('offline_' + i, l.text.trim(), new Box(l.x * sx, l.y * sy, l.width * sx, l.height * sy));
      line.words = l.words.filter((w: NativeWord) => w.text.trim().length > 0).map((w: NativeWord, j: number) => {
        return new OcrLine('offline_' + i + '_word_' + j, w.text.trim(), new Box(w.x * sx, w.y * sy, w.width * sx, w.height * sy));
      });
      return line;
    });
  }
}
