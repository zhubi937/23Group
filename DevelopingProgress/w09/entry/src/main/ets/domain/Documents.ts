export function xmlText(xml: string): string {
  return xml.replace(/<w:tab\b[^>]*\/>/g,'\t').replace(/<w:br\b[^>]*\/>/g,'\n').replace(/<\/w:p>/g,'\n').replace(/<[^>]*>/g,'')
    .replace(/&#x([\da-f]+);/gi,(_all:string,n:string)=>String.fromCodePoint(parseInt(n,16)))
    .replace(/&#(\d+);/g,(_all:string,n:string)=>String.fromCodePoint(parseInt(n,10)))
    .replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&apos;/g,"'").replace(/&amp;/g,'&').trim();
}
export function validateDocx(data: Uint8Array): void {
  const u16=(p:number):number=>data[p]+data[p+1]*256;
  const u32=(p:number):number=>(u16(p)+u16(p+2)*65536)>>>0;
  let end=-1;
  for(let p=data.length-22;p>=Math.max(0,data.length-65557);p--) { if(u32(p)===0x06054b50) { end=p; break; } }
  if(end<0 || u16(end+4)!==0 || u16(end+6)!==0 || u16(end+8)!==u16(end+10)) { throw new Error('不支持的 Word 压缩格式'); }
  const count=u16(end+10); let pos=u32(end+16),total=0,found=false;
  if(count>1000 || pos>=end) { throw new Error('Word 文档过大'); }
  for(let i=0;i<count;i++) {
    if(pos+46>data.length || u32(pos)!==0x02014b50) { throw new Error('Word 文件目录损坏'); }
    const len=u16(pos+28),extra=u16(pos+30),comment=u16(pos+32); let name='';
    if(pos+46+len+extra+comment>end) { throw new Error('Word 文件目录越界'); }
    for(let j=0;j<len;j++) { name+=String.fromCharCode(data[pos+46+j]); }
    const size=u32(pos+24); total+=size;
    if(name.includes('..') || name.startsWith('/') || name.includes('\\') || name.includes(':') || ((u32(pos+38)>>>16)&0xF000)===0xA000 || size>8*1024*1024 || total>24*1024*1024) { throw new Error('Word 文件包含不安全路径或解压体积过大'); }
    if(name==='word/document.xml') { found=true; }
    pos+=46+len+extra+comment;
  }
  if(!found) { throw new Error('请选择 .docx 文档，旧版 .doc 请先另存为 .docx'); }
}
export class WordEntry { data: ArrayBuffer=new ArrayBuffer(0); size: number=0; crc: number=0; method: number=0; }
export function wordEntry(data: Uint8Array): WordEntry {
  validateDocx(data);
  const u16=(p:number):number=>data[p]+data[p+1]*256;
  const u32=(p:number):number=>(u16(p)+u16(p+2)*65536)>>>0;
  let end=data.length-22;while(end>=0 && u32(end)!==0x06054b50){end--;}
  let pos=u32(end+16);
  for(let i=0;i<u16(end+10);i++) {
    const len=u16(pos+28),extra=u16(pos+30),comment=u16(pos+32);let name='';for(let j=0;j<len;j++){name+=String.fromCharCode(data[pos+46+j]);}
    if(name==='word/document.xml') {
      const entry=new WordEntry();entry.method=u16(pos+10);entry.crc=u32(pos+16);entry.size=u32(pos+24);const compressed=u32(pos+20),local=u32(pos+42);
      if(local+30>pos || u32(local)!==0x04034b50 || u16(local+8)!==entry.method || (u16(pos+8)&1)!==0 || ![0,8].includes(entry.method)) {throw new Error('Word 文件头不一致或已加密');}
      let localName='';const n=u16(local+26);for(let j=0;j<n;j++){localName+=String.fromCharCode(data[local+30+j]);}
      const start=local+30+n+u16(local+28);
      if(localName!==name || start+compressed>u32(end+16) || entry.size>4*1024*1024) {throw new Error('Word 正文损坏或超出4 MB限制');}
      entry.data=data.slice(start,start+compressed).buffer;return entry;
    }
    pos+=46+len+extra+comment;
  }
  throw new Error('缺少 Word 正文');
}
