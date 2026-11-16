import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { SourceRecord, uid } from '../domain/Models';

export class ImportResult {
  source: SourceRecord;
  duplicate: boolean = false;
  constructor(s: SourceRecord, duplicate: boolean = false) { this.source = s; this.duplicate = duplicate; }
}
export class Images {
  private context: common.UIAbilityContext; constructor(context: common.UIAbilityContext) { this.context = context; }
  async choose(): Promise<string> {
    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1 });
    return result.photoUris.length ? result.photoUris[0] : '';
  }
  async fingerprint(fd: number): Promise<string> {
    const md = cryptoFramework.createMd('SHA256'); const chunk = new ArrayBuffer(256 * 1024); 
    while (true) {
      const n = await fs.read(fd, chunk, { length: chunk.byteLength });
      if (n === 0) { break; }
      await md.update({ data: new Uint8Array(chunk.slice(0, n)) });
    }
    const result = await md.digest(); let hex = '';
    for (let i = 0; i < result.data.length; i++) { hex += result.data[i].toString(16).padStart(2, '0'); }
    return hex;
  }
  async importUri(uri: string): Promise<SourceRecord> {
    const f = await fs.open(uri, fs.OpenMode.READ_ONLY);
    const s = new SourceRecord(); s.id = uid('source'); s.createdAt = Date.now(); s.name = '截图 ' + new Date(s.createdAt).toLocaleString();
    let copied = false;
    try {
      const stat = await fs.stat(f.fd);
      if (stat.size > 20 * 1024 * 1024 || stat.size === 0) { throw new Error('请选择不超过20 MB的有效图片'); }
      s.hash = await this.fingerprint(f.fd);
      const dir = this.context.filesDir + '/sources'; if (!fs.accessSync(dir)) { fs.mkdirSync(dir); }
      s.path = dir + '/' + s.id + '.img';
      await fs.copyFile(f.fd, s.path); copied = true;
      const local = await fs.open(s.path, fs.OpenMode.READ_ONLY);
      try {
        const source = image.createImageSource(local.fd);
        try { const info = await source.getImageInfo(); s.width = info.size.width; s.height = info.size.height; }
        finally { source.release(); }
      } finally { fs.closeSync(local); }
      if (s.width * s.height > 40000000) { throw new Error('图片分辨率过大，请先裁剪后再导入'); }
      return s;
    } catch (e) { if (copied) { try { fs.unlinkSync(s.path); } catch (_) {} } throw new Error((e as Error).message || String(e)); }
    finally { fs.closeSync(f); }
  }
  remove(s: SourceRecord): void {
    // Only files in the application's own source directory may be removed.
    const prefix = this.context.filesDir + '/sources/';
    if (s.path.startsWith(prefix) && !s.path.includes('..') && fs.accessSync(s.path)) { fs.unlinkSync(s.path); }
  }
  clearSources(): void {
    const dir = this.context.filesDir + '/sources';
    if (!fs.accessSync(dir)) { return; }
    fs.listFileSync(dir).forEach((name: string) => { if (!name.includes('/') && !name.includes('\\') && !name.includes('..')) { fs.unlinkSync(dir + '/' + name); } });
  }
  async sample(name: string): Promise<SourceRecord> {
    const data = await this.context.resourceManager.getRawFileContent('samples/' + name + '.png');
    const dir = this.context.filesDir + '/sources'; if (!fs.accessSync(dir)) { fs.mkdirSync(dir); }
    const path = dir + '/fixture-' + name + '.png';
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try { fs.writeSync(file.fd, data.buffer); } finally { fs.closeSync(file); }
    try { return await this.importUri(path); } finally { if (fs.accessSync(path)) { fs.unlinkSync(path); } }
  }
}


