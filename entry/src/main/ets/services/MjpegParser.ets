/** Parse multipart frames by Content-Length, including split headers/JPEGs. */
export class MjpegParser {
  private buffer: Uint8Array = new Uint8Array(0);
  private frameLength: number = 0;
  private partSequence: number = -1;
  sequence: number = -1;
  private readonly maxFrameBytes: number = 1024 * 1024;

  reset(): void {
    this.buffer = new Uint8Array(0);
    this.frameLength = 0;
    this.partSequence = this.sequence = -1;
  }

  push(chunk: ArrayBuffer): ArrayBuffer | null {
    const bytes = new Uint8Array(chunk);
    if (this.buffer.length + bytes.length > this.maxFrameBytes + 8192) {
      throw new Error('视频帧超过接收上限');
    }
    const joined = new Uint8Array(this.buffer.length + bytes.length);
    joined.set(this.buffer);
    joined.set(bytes, this.buffer.length);
    this.buffer = joined;
    let latest: ArrayBuffer | null = null;
    while (this.buffer.length > 0) {
      if (this.frameLength === 0) {
        let end: number = -1;
        for (let i = 0; i + 3 < this.buffer.length; i++) {
          if (this.buffer[i] === 13 && this.buffer[i + 1] === 10 &&
            this.buffer[i + 2] === 13 && this.buffer[i + 3] === 10) { end = i; break; }
        }
        if (end < 0) {
          if (this.buffer.length > 8192) { throw new Error('视频流头部无效'); }
          break;
        }
        let header: string = '';
        for (let i = 0; i < end; i++) { header += String.fromCharCode(this.buffer[i]); }
        const length = /Content-Length:\s*(\d+)/i.exec(header);
        if (length === null || !header.includes('image/jpeg')) { throw new Error('视频流格式无效'); }
        this.frameLength = Number(length[1]);
        const sequence = /X-Frame-Sequence:\s*(\d+)/i.exec(header);
        this.partSequence = sequence === null ? -1 : Number(sequence[1]);
        if (this.frameLength <= 0 || this.frameLength > this.maxFrameBytes) {
          throw new Error('视频帧长度无效');
        }
        this.buffer = this.buffer.slice(end + 4);
      }
      if (this.buffer.length < this.frameLength) { break; }
      latest = this.buffer.slice(0, this.frameLength).buffer as ArrayBuffer;
      this.sequence = this.partSequence;
      this.buffer = this.buffer.slice(this.frameLength);
      this.frameLength = 0;
    }
    // Multiple complete frames in a packet: decode only the newest one.
    return latest;
  }
}
