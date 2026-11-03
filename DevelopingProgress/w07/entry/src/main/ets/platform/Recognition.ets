import { textRecognition } from '@kit.CoreVisionKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SourceRecord, OcrLine, Box } from '../domain/Models';
import { extract } from '../domain/Rules';
import { OfflineRecognition } from './OfflineRecognition';

export class Recognition {
  private context: common.UIAbilityContext | null = null;
  setContext(context: common.UIAbilityContext): void { this.context = context; }
  isAvailable(): boolean { return canIUse('SystemCapability.AI.OCR.TextRecognition'); }
  async run(s: SourceRecord): Promise<void> {
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    let pixels: image.PixelMap | null = null;
    let initialized = false;
    const systemAvailable = this.isAvailable();
    let systemError = '';
    try {
      file = fs.openSync(s.path, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const scale = Math.min(systemAvailable ? 1 : 2, (systemAvailable ? 2400 : 2600) / Math.max(s.width, s.height));
      pixels = await source.createPixelMap({ desiredSize: { width: Math.max(1, Math.round(s.width * scale)), height: Math.max(1, Math.round(s.height * scale)) }, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      const info = await pixels.getImageInfo();
      let lines: OcrLine[] = [];
      if (systemAvailable) {
        try {
          initialized = await textRecognition.init();
          if (!initialized) { throw new Error('系统文字识别服务未就绪'); }
          const result = await textRecognition.recognizeText({ pixelMap: pixels });
          const sx = s.width / info.size.width; const sy = s.height / info.size.height; let n = 0;
          result.blocks.forEach((block: textRecognition.TextBlock) => {
            block.lines.forEach((line: textRecognition.TextLine) => {
              const xs = line.cornerPoints.map((p: textRecognition.PixelPoint) => p.x * sx);
              const ys = line.cornerPoints.map((p: textRecognition.PixelPoint) => p.y * sy);
              if (!xs.length || !line.value.trim()) { return; }
              const left = Math.max(0, Math.min(...xs)); const top = Math.max(0, Math.min(...ys));
              lines.push(new OcrLine('line_' + n++, line.value, new Box(left, top, Math.min(s.width, Math.max(...xs)) - left, Math.min(s.height, Math.max(...ys)) - top)));
            });
          });
        } catch (e) { systemError = (e as Error).message || String(e); }
      }
      let mode = 'system';
      if (!lines.length) {
        if (!this.context) { throw new Error('应用上下文未就绪，请返回后重试'); }
        lines = await new OfflineRecognition().run(pixels, s.width, s.height, this.context);
        mode = 'offline';
      }
      if (!lines.length) { throw new Error('没有识别到可读文字，请裁剪放大正文后重试'); }
      s.lines = lines; s.mode = mode; s.ocrState = 'recognized'; s.error = '';
      s.diagnostic = mode === 'offline' ? 'Tesseract 5.5.0; chi_sim+eng; ' + (systemError || 'system OCR syscap=' + systemAvailable) : '';
      s.candidates = extract(lines, s.createdAt).fields;
    } catch (e) {
      const err = e as BusinessError;
      s.ocrState = 'failed'; s.diagnostic = String(err.code || '') + ': ' + (err.message || String(e));
      s.error = '图片识别未完成，原图和已有文字已保留：' + (err.message || '请重试');
    } finally {
      if (pixels) { try { await pixels.release(); } catch (_) {} }
      if (source) { try { await source.release(); } catch (_) {} }
      if (file) { try { fs.closeSync(file.fd); } catch (_) {} }
      if (initialized) { try { await textRecognition.release(); } catch (_) {} }
    }
  }
}
