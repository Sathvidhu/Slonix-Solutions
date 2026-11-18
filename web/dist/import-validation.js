// Shared, deterministic validation. Parsing never executes document formulas or scripts.
export const requiredColumns=['name','phone','institution'];
const aliases={name:['name','contactname','fullname','studentname'],phone:['phone','phonenumber','mobile','mobilenumber','contactnumber'],institution:['institution','institutionname','college','school','university'],email:['email','emailaddress']};
export const canonicalHeader=value=>Object.entries(aliases).find(([,names])=>names.includes(String(value??'').toLowerCase().replace(/[^a-z0-9]/g,'')))?.[0]||null;
export function validateContactRows(rows,existing=[]){
 const errors=[],contacts=[];if(!rows.length)return {contacts,errors:['The file has no rows. Include Contact name, Phone and Institution headers.'],duplicates:0};
 const headers=rows[0].map(canonicalHeader),missing=requiredColumns.filter(c=>!headers.includes(c));
 if(missing.length)return {contacts,errors:[`Missing required column(s): ${missing.map(s=>s==='name'?'Contact name':s[0].toUpperCase()+s.slice(1)).join(', ')}. Upload the file with the full required content.`],duplicates:0};
 const repeated=headers.filter((h,i)=>h&&headers.indexOf(h)!==i);if(repeated.length)return {contacts,errors:[`Duplicate column headers: ${[...new Set(repeated)].join(', ')}.`],duplicates:0};
 if(rows.length>501)return {contacts,errors:['A single import supports up to 500 contacts. Split this file into smaller files.'],duplicates:0};
 const seen=new Set(existing.map(c=>String(c.phone||'').replace(/\D/g,'')));let duplicates=0;
 for(let i=1;i<rows.length;i++){
  const row=rows[i];if(row.every(v=>v==null||String(v).trim()===''))continue;
  const record={};headers.forEach((h,j)=>{if(h)record[h]=row[j]==null?'':String(row[j]).trim()});
  const absent=requiredColumns.filter(c=>!record[c]);if(absent.length){errors.push(`Row ${i+1}: missing ${absent.map(s=>s==='name'?'Contact name':s).join(', ')}.`);continue;}
  const digits=record.phone.replace(/\D/g,'');if(!/^\+?[\d\s()-]+$/.test(record.phone)||digits.length<7||digits.length>15){errors.push(`Row ${i+1}: Phone must contain 7–15 digits. Format phone cells as Text in Excel.`);continue;}
  if(record.email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(record.email)){errors.push(`Row ${i+1}: Email is invalid (or remove it; email is optional).`);continue;}
  if(seen.has(digits)){duplicates++;continue;}seen.add(digits);
  contacts.push({name:record.name,phone:record.phone,institution:record.institution,email:record.email||'',status:'New',notes:'',assigned_employee_id:null,follow_up_at:null});
 }
 if(!contacts.length&&!errors.length)errors.push(duplicates?'Every contact is already present or duplicated in this file.':'No contact data was found below the headers.');
 return {contacts,errors,duplicates};
}
export function pipeRows(text){return String(text).split(/\r?\n/).filter(v=>v.trim()).map(line=>line.split('|').map(v=>v.trim()));}
export function pdfItemsToRows(pages){
 const result=[];let columnPositions=null;let sawHeader=false;
 for(const items of pages){const lines=[];for(const item of items){if(!item.str?.trim())continue;const x=item.transform[4],y=item.transform[5];let line=lines.find(l=>Math.abs(l.y-y)<3);if(!line){line={y,items:[]};lines.push(line);}line.items.push({x,text:item.str.trim()});}
  lines.sort((a,b)=>b.y-a.y);
  for(const line of lines){line.items.sort((a,b)=>a.x-b.x);const text=line.items.map(i=>i.text).join(' ');
   if(text.includes('|')){const row=text.split('|').map(s=>s.trim()).filter((v,i,a)=>!(v===''&&(i===0||i===a.length-1)));if(requiredColumns.every(c=>row.map(canonicalHeader).includes(c))){if(!sawHeader){result.push(row);sawHeader=true;}continue;}if(sawHeader)result.push(row);continue;}
   const headerItems=line.items.filter(v=>canonicalHeader(v.text));
   if(requiredColumns.every(c=>headerItems.some(h=>canonicalHeader(h.text)===c))){columnPositions=headerItems.map(h=>({x:h.x,key:canonicalHeader(h.text)}));if(!sawHeader){result.push(columnPositions.map(c=>c.key));sawHeader=true;}continue;}
   if(sawHeader&&columnPositions){const row=columnPositions.map(()=>[]);for(const item of line.items){let index=0;for(let j=1;j<columnPositions.length;j++){if(item.x>=columnPositions[j].x-8)index=j;}row[index].push(item.text);}const values=row.map(v=>v.join(' '));if(values.some(v=>/\d{7}/.test(v.replace(/\s/g,'')))||values.filter(Boolean).length>1)result.push(values);}
  }
 }
 return result;
}
