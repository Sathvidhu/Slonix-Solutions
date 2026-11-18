import {build} from 'esbuild';
import {mkdir,copyFile} from 'node:fs/promises';
await mkdir(new URL('../dist/vendor/',import.meta.url),{recursive:true});
await build({entryPoints:[new URL('../contact-import-entry.js',import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1')],bundle:true,format:'esm',platform:'browser',target:['es2022'],minify:true,outfile:new URL('../dist/contact-import.js',import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1'),legalComments:'eof'});
await copyFile(new URL('../node_modules/pdfjs-dist/build/pdf.worker.min.mjs',import.meta.url),new URL('../dist/vendor/pdf.worker.min.mjs',import.meta.url));
console.log('Built local Excel/PDF import parser and PDF worker.');
