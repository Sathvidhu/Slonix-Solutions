import test from 'node:test';
import assert from 'node:assert/strict';
import {validateContactRows,pdfItemsToRows,pipeRows} from '../dist/import-validation.js';
import {Repository} from '../dist/api.js';
import {workbook} from '../dist/xlsx.js';
import readExcel from 'read-excel-file/node';
const memory=()=>{const m=new Map();return {getItem:k=>m.get(k)||null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)}};
globalThis.window={MONTME_CONFIG:{}};globalThis.localStorage=memory();globalThis.sessionStorage=memory();
test('Import identifies missing required headers and individual row fields before saving',()=>{
 assert.match(validateContactRows([['Name','Phone'],['Asha','9876543210']]).errors[0],/Institution/);
 const r=validateContactRows([['Contact name','Phone','Institution','Email'],['Asha','9876543210','',''],['','9876543211','College','']]);
 assert.deepEqual(r.errors,['Row 2: missing institution.','Row 3: missing Contact name.']);
});
test('Import preserves text phones, validates email and skips duplicate numbers',()=>{
 const r=validateContactRows(pipeRows('Contact name | Phone | Institution | Email\nAsha | 00123456789 | College | asha@example.com\nB | 00123456789 | School |'));
 assert.equal(r.contacts[0].phone,'00123456789');assert.equal(r.duplicates,1);assert.equal(r.errors.length,0);
 assert.match(validateContactRows([['name','phone','institution','email'],['A','9876543210','College','bad']]).errors[0],/Email is invalid/);
});
test('Real XLSX template parses with the pinned Excel reader',async()=>{
 const sheets=await readExcel(Buffer.from(workbook([['Contact name','Phone','Institution','Email'],['Asha','00123456789','Example Institute','asha@example.com']])));
 assert.equal(sheets.length,1);const result=validateContactRows(sheets[0].data);assert.equal(result.errors.length,0);assert.equal(result.contacts[0].institution,'Example Institute');assert.equal(result.contacts[0].phone,'00123456789');
});
test('Text PDF column extraction identifies the required fields without guessing scanned content',()=>{
 const item=(str,x,y)=>({str,transform:[1,0,0,1,x,y]});
 const rows=pdfItemsToRows([[item('Name',40,750),item('Phone',170,750),item('Institution',300,750),item('Asha',40,725),item('9876543210',170,725),item('College',300,725)]]);
 assert.equal(validateContactRows(rows).errors.length,0);assert.deepEqual(pdfItemsToRows([[]]),[]);
});
test('Preview employee passwords are discarded instead of entering browser storage',async()=>{
 const r=new Repository(true);await r.load();await r.saveEmployee({name:'Test',employee_code:'EMP01',email:'test@example.com',password:'never-store-this',active:true});
 assert.equal(JSON.stringify(r.data).includes('never-store-this'),false);assert.equal(localStorage.getItem('montme.admin.local.v1').includes('never-store-this'),false);
});
