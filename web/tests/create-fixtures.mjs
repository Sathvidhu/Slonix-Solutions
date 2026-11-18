import {writeFile,mkdir} from 'node:fs/promises';
import {workbook} from '../dist/xlsx.js';
const dir=new URL('./fixtures/',import.meta.url);await mkdir(dir,{recursive:true});
await writeFile(new URL('contacts-valid.xlsx',dir),workbook([['Contact name','Phone','Institution','Email'],['Preview Contact','9876543210','Example Institute','preview@example.com']]));
await writeFile(new URL('contacts-missing.xlsx',dir),workbook([['Contact name','Phone'],['Preview Contact','9876543210']]));
function pdf(text){const stream=`BT /F1 11 Tf 40 780 Td (${text[0]}) Tj 0 -25 Td (${text[1]||''}) Tj ET`,objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>','<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',`<< /Length ${Buffer.byteLength(stream)} >>\nstream\n${stream}\nendstream`];let out='%PDF-1.4\n',offsets=[0];objects.forEach((o,i)=>{offsets.push(Buffer.byteLength(out));out+=`${i+1} 0 obj\n${o}\nendobj\n`});const xref=Buffer.byteLength(out);out+=`xref\n0 6\n0000000000 65535 f \n`+offsets.slice(1).map(n=>`${String(n).padStart(10,'0')} 00000 n \n`).join('')+`trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;return out;}
await writeFile(new URL('contacts-valid.pdf',dir),pdf(['Contact name | Phone | Institution | Email','Preview Contact | 9876543210 | Example Institute | preview@example.com']));
await writeFile(new URL('contacts-empty.pdf',dir),pdf(['','']));
console.log('Created non-production import fixtures.');
