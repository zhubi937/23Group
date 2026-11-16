from pathlib import Path
import zipfile
p=Path(__file__).parent/'fixtures';p.mkdir(exist_ok=True)
text='通知：提交移动应用作业\n日期：2027-01-01\n提交截止：2027-01-01 23:59\n地点：创新楼301'
(p/'notice.txt').write_text(text,encoding='utf8')
xml='<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'+''.join('<w:p><w:r><w:t>'+s+'</w:t></w:r></w:p>' for s in text.splitlines())+'</w:body></w:document>'
with zipfile.ZipFile(p/'notice.docx','w',zipfile.ZIP_DEFLATED) as z:
    z.writestr('word/document.xml',xml)
    z.writestr('[Content_Types].xml','<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
# Small standards-compliant, independently authored text PDF; no third-party PDF library.
stream=b'BT /F1 16 Tf 50 760 Td (Deadline 2027-01-01 23:59) Tj ET'
objects=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'\nendstream']
data=b'%PDF-1.4\n';offsets=[0]
for i,obj in enumerate(objects,1):offsets.append(len(data));data+=f'{i} 0 obj\n'.encode()+obj+b'\nendobj\n'
start=len(data);data+=f'xref\n0 {len(objects)+1}\n0000000000 65535 f \n'.encode()+b''.join(f'{o:010d} 00000 n \n'.encode() for o in offsets[1:])+f'trailer\n<< /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n'.encode()
(p/'notice.pdf').write_bytes(data)
# Embed the existing RGB PNG losslessly as a PDF image, without editing the image.
import struct
png=(Path(__file__).parents[1]/'entry/src/main/resources/rawfile/samples/notice.png').read_bytes()
w,h,depth,color=struct.unpack('>IIBB',png[16:26]);assert depth==8 and color==2
parts=[];at=8
while at<len(png):
    size=int.from_bytes(png[at:at+4],'big');kind=png[at+4:at+8]
    if kind==b'IDAT':parts.append(png[at+8:at+8+size])
    at+=size+12
pixels=b''.join(parts);content=f'q {w} 0 0 {h} 0 0 cm /Im1 Do Q'.encode()
objects=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {w} {h}] /Resources << /XObject << /Im1 4 0 R >> >> /Contents 5 0 R >>'.encode(),f'<< /Type /XObject /Subtype /Image /Width {w} /Height {h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors 3 /BitsPerComponent 8 /Columns {w} >> /Length {len(pixels)} >>\nstream\n'.encode()+pixels+b'\nendstream',f'<< /Length {len(content)} >>\nstream\n'.encode()+content+b'\nendstream']
data=b'%PDF-1.4\n';offsets=[0]
for i,obj in enumerate(objects,1):offsets.append(len(data));data+=f'{i} 0 obj\n'.encode()+obj+b'\nendobj\n'
start=len(data);data+=f'xref\n0 {len(objects)+1}\n0000000000 65535 f \n'.encode()+b''.join(f'{o:010d} 00000 n \n'.encode() for o in offsets[1:])+f'trailer\n<< /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n'.encode()
(p/'scanned.pdf').write_bytes(data)
print('Created original text, DOCX and PDF fixtures.')
