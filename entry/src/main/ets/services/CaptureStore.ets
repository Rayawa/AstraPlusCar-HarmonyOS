import { fileIo, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export interface CaptureItem {
  name: string;
  uri: string;
  time: string;
}

/** App-owned captures survive restarts and can be removed without media-library permissions. */
export class CaptureStore {
  private readonly directory: string;

  constructor(context: common.UIAbilityContext) {
    this.directory = `${context.filesDir}/captures`;
    try { fileIo.mkdirSync(this.directory); } catch (error) { /* Already exists. */ }
  }

  private formatTime(stamp: number): string {
    const date = new Date(stamp);
    const pad = (value: number): string => value.toString().padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
      `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
  }

  list(): CaptureItem[] {
    const names = fileIo.listFileSync(this.directory)
      .filter((name: string) => /^astra-\d+-\d+\.jpg$/.test(name))
      .sort((a: string, b: string) => b.localeCompare(a));
    return names.map((name: string): CaptureItem => {
      const stamp = Number(name.split('-')[1]);
      return { name: name, uri: fileUri.getUriFromPath(`${this.directory}/${name}`),
        time: this.formatTime(stamp) };
    });
  }

  save(jpeg: ArrayBuffer): CaptureItem {
    const name = `astra-${Date.now()}-${Math.floor(Math.random() * 10000)}.jpg`;
    const path = `${this.directory}/${name}`;
    const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
    try {
      let written = 0;
      while (written < jpeg.byteLength) {
        const count = fileIo.writeSync(file.fd, jpeg.slice(written));
        if (count <= 0) { throw new Error('本地截图写入失败'); }
        written += count;
      }
    } catch (error) {
      fileIo.closeSync(file);
      fileIo.unlinkSync(path);
      throw new Error((error as Error).message);
    }
    fileIo.closeSync(file);
    return { name: name, uri: fileUri.getUriFromPath(path), time: this.formatTime(Date.now()) };
  }

  remove(name: string): void {
    if (!/^astra-\d+-\d+\.jpg$/.test(name)) { throw new Error('截图名称无效'); }
    fileIo.unlinkSync(`${this.directory}/${name}`);
  }
}
