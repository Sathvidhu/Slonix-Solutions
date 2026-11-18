import readXlsxFile from 'read-excel-file/browser';
import {getDocument,GlobalWorkerOptions} from 'pdfjs-dist';
import {validateContactRows,pdfItemsToRows} from './dist/import-validation.js';
GlobalWorkerOptions.workerSrc=new URL('./vendor/pdf.worker.min.mjs',import.meta.url).href;
export async function parseContactFile(file,existing=[]){
 if(!file||!file.size)throw Error('Choose a nonempty Excel (.xlsx) or PDF file.');
 if(file.size>20*1024*1024)throw Error('Contact imports are limited to 20 MB.');
 const ext=file.name.split('.').pop().toLowerCase();let rows;
 if(ext==='xlsx'){
  try{const sheets=await readXlsxFile(file);if(sheets.length!==1)throw Error('Use a workbook with exactly one contact sheet so the import is unambiguous.');rows=sheets[0].data;}catch(e){throw Error(`Excel could not be read: ${e.message}`);}
 }else if(ext==='pdf'){
  const task=getDocument({data:new Uint8Array(await file.arrayBuffer()),isEvalSupported:false,useSystemFonts:true,disableFontFace:true});
  let doc;try{doc=await task.promise;if(doc.numPages>50)throw Error('PDF imports support up to 50 pages.');const pages=[];for(let i=1;i<=doc.numPages;i++){const page=await doc.getPage(i);pages.push((await page.getTextContent()).items);page.cleanup();}rows=pdfItemsToRows(pages);if(!rows.length)throw Error('No readable contact table found. Scanned/image-only PDFs require OCR first. Upload a text-based PDF or Excel containing Contact name, Phone and Institution headers.');}finally{try{await task.destroy();}catch{}}
 }else throw Error('Use Excel .xlsx or a text-based .pdf. Convert legacy .xls files to .xlsx first.');
 return validateContactRows(rows,existing);
}
